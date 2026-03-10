local M = {}

local config = require("sade.config")

local SPINNER_FRAMES = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }
local SIGN_GROUP = "sade_heartbeat"

---@class HeartbeatState
local state = {
  watchers = {},           -- path → uv_fs_event_t
  timers = {},             -- path → uv_timer_t (debounce)
  active = {},             -- path → timestamp of last change
  spinner_timer = nil,     -- uv_timer_t for animation loop
  spinner_frame = 1,       -- current frame index
  ns = nil,                -- namespace id
  batch = {},              -- files changed in current burst (for bulk notification)
  batch_timer = nil,       -- timer for batching notifications
}

--- Define signs for each spinner frame + settled state.
local function ensure_signs()
  if state.ns then
    return
  end
  state.ns = vim.api.nvim_create_namespace("sade_heartbeat")
  for i, frame in ipairs(SPINNER_FRAMES) do
    vim.fn.sign_define("SadeSpinner" .. i, { text = frame, texthl = "DiagnosticWarn" })
  end
  vim.fn.sign_define("SadeSettled", { text = "○", texthl = "DiagnosticInfo" })
end

--- Find buffer number for a file path, if loaded.
---@param filepath string
---@return number|nil
local function find_buf(filepath)
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) then
      if vim.api.nvim_buf_get_name(buf) == filepath then
        return buf
      end
    end
  end
  return nil
end

--- Place the current spinner frame sign on all active buffers.
local function tick_spinner()
  state.spinner_frame = (state.spinner_frame % #SPINNER_FRAMES) + 1
  local sign_name = "SadeSpinner" .. state.spinner_frame

  for filepath, _ in pairs(state.active) do
    local bufnr = find_buf(filepath)
    if bufnr then
      vim.fn.sign_unplace(SIGN_GROUP, { buffer = bufnr })
      vim.fn.sign_place(0, SIGN_GROUP, sign_name, bufnr, { lnum = 1, priority = 50 })
    end
  end
end

--- Start the spinner animation loop if not already running.
local function start_spinner()
  if state.spinner_timer then
    return
  end
  local interval = config.values.heartbeat.spinner_ms
  state.spinner_timer = vim.uv.new_timer()
  state.spinner_timer:start(0, interval, function()
    vim.schedule(tick_spinner)
  end)
end

--- Stop the spinner animation loop.
local function stop_spinner()
  if state.spinner_timer then
    state.spinner_timer:stop()
    state.spinner_timer:close()
    state.spinner_timer = nil
  end
end

--- Transition a file from active → settled → clear.
---@param filepath string
local function settle_file(filepath)
  state.active[filepath] = nil

  -- stop spinner if no more active files
  if next(state.active) == nil then
    stop_spinner()
  end

  -- show settled sign briefly
  local bufnr = find_buf(filepath)
  if bufnr then
    vim.fn.sign_unplace(SIGN_GROUP, { buffer = bufnr })
    vim.fn.sign_place(0, SIGN_GROUP, "SadeSettled", bufnr, { lnum = 1, priority = 50 })

    -- clear after a short fade
    vim.defer_fn(function()
      -- only clear if file hasn't become active again
      if not state.active[filepath] then
        local b = find_buf(filepath)
        if b then
          vim.fn.sign_unplace(SIGN_GROUP, { buffer = b })
        end
      end
    end, 1000)
  end
end

--- Track a file change for bulk notification.
---@param filepath string
local function track_batch(filepath)
  state.batch[filepath] = true

  -- reset the batch timer
  if state.batch_timer then
    state.batch_timer:stop()
    state.batch_timer:close()
    state.batch_timer = nil
  end

  local batch_ms = config.values.heartbeat.settle_ms + 500
  state.batch_timer = vim.uv.new_timer()
  state.batch_timer:start(batch_ms, 0, function()
    state.batch_timer:stop()
    state.batch_timer:close()
    state.batch_timer = nil

    vim.schedule(function()
      local count = vim.tbl_count(state.batch)
      if count > 1 then
        vim.notify(("[sade] %d files updated"):format(count))
      end
      state.batch = {}
    end)
  end)
end

--- Reload a buffer from disk if it exists and hasn't been modified by the user.
---@param filepath string
local function reload_buf(filepath)
  local bufnr = find_buf(filepath)
  if not bufnr then
    return
  end
  if vim.bo[bufnr].modified then
    return
  end
  vim.api.nvim_buf_call(bufnr, function()
    vim.cmd("checktime")
  end)
end

--- Handle a file change event (called after debounce).
---@param filepath string
local function on_file_changed(filepath)
  vim.schedule(function()
    state.active[filepath] = vim.uv.now()

    reload_buf(filepath)
    track_batch(filepath)

    -- start spinner if this is the first active file
    ensure_signs()
    start_spinner()

    -- schedule settle check
    local settle_ms = config.values.heartbeat.settle_ms
    vim.defer_fn(function()
      local last = state.active[filepath]
      if last and (vim.uv.now() - last) >= settle_ms then
        settle_file(filepath)
      end
    end, settle_ms + 50)
  end)
end

--- Start watching a directory recursively for changes.
---@param dir string
local function watch_dir(dir)
  if state.watchers[dir] then
    return
  end

  local handle = vim.uv.new_fs_event()
  if not handle then
    return
  end

  local debounce_ms = config.values.heartbeat.debounce_ms

  handle:start(dir, { recursive = true }, function(err, filename, events)
    if err or not filename then
      return
    end
    if not (events.change or events.rename) then
      return
    end

    local filepath = dir .. "/" .. filename

    if filepath:match("/.git/") or filepath:match("/.sade/") then
      return
    end

    -- debounce per file
    if state.timers[filepath] then
      state.timers[filepath]:stop()
      state.timers[filepath]:close()
      state.timers[filepath] = nil
    end

    local timer = vim.uv.new_timer()
    state.timers[filepath] = timer
    timer:start(debounce_ms, 0, function()
      timer:stop()
      timer:close()
      state.timers[filepath] = nil
      on_file_changed(filepath)
    end)
  end)

  state.watchers[dir] = handle
end

--- Start the heartbeat: watch the project root for file changes.
---@param project_root string
function M.start(project_root)
  ensure_signs()
  watch_dir(project_root)
  vim.notify("[sade] heartbeat started")
end

--- Stop all watchers and clear state (silent).
function M.stop_silent()
  stop_spinner()

  for path, handle in pairs(state.watchers) do
    handle:stop()
    handle:close()
    state.watchers[path] = nil
  end
  for path, timer in pairs(state.timers) do
    timer:stop()
    timer:close()
    state.timers[path] = nil
  end
  if state.batch_timer then
    state.batch_timer:stop()
    state.batch_timer:close()
    state.batch_timer = nil
  end

  state.active = {}
  state.batch = {}
  vim.fn.sign_unplace(SIGN_GROUP)
end

--- Stop all watchers and clear state.
function M.stop()
  M.stop_silent()
  vim.notify("[sade] heartbeat stopped")
end

--- Check if a file is currently active (being modified).
---@param filepath string
---@return boolean
function M.is_active(filepath)
  return state.active[filepath] ~= nil
end

--- Get all currently active file paths.
---@return string[]
function M.active_files()
  local files = {}
  for path, _ in pairs(state.active) do
    table.insert(files, path)
  end
  return files
end

return M
