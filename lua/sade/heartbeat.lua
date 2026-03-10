local M = {}

---@class HeartbeatState
---@field watchers table<string, uv_fs_event_t>  path → fs_event handle
---@field timers table<string, uv_timer_t>        path → debounce timer
---@field active table<string, number>             path → timestamp of last change
---@field ns number                                 sign namespace id
---@field sign_group string

local state = {
  watchers = {},
  timers = {},
  active = {},
  ns = nil,
  sign_group = "sade_heartbeat",
}

local config = require("sade.config")

--- Get or create the namespace and sign.
local function ensure_signs()
  if not state.ns then
    state.ns = vim.api.nvim_create_namespace("sade_heartbeat")
    vim.fn.sign_define("SadeActive", { text = "●", texthl = "DiagnosticWarn" })
    vim.fn.sign_define("SadeSettled", { text = "○", texthl = "DiagnosticInfo" })
  end
end

--- Place a sign on a buffer indicating activity.
---@param bufnr number
---@param sign_name string
local function place_sign(bufnr, sign_name)
  -- clear existing heartbeat signs on this buffer
  vim.fn.sign_unplace(state.sign_group, { buffer = bufnr })
  vim.fn.sign_place(0, state.sign_group, sign_name, bufnr, { lnum = 1, priority = 50 })
end

--- Clear heartbeat signs from a buffer.
---@param bufnr number
local function clear_sign(bufnr)
  vim.fn.sign_unplace(state.sign_group, { buffer = bufnr })
end

--- Find buffer number for a file path, if loaded.
---@param filepath string
---@return number|nil
local function find_buf(filepath)
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) then
      local name = vim.api.nvim_buf_get_name(buf)
      if name == filepath then
        return buf
      end
    end
  end
  return nil
end

--- Reload a buffer from disk if it exists and hasn't been modified.
---@param filepath string
local function reload_buf(filepath)
  local bufnr = find_buf(filepath)
  if not bufnr then
    return
  end

  -- don't clobber unsaved user work
  if vim.bo[bufnr].modified then
    return
  end

  -- use checktime to trigger Neovim's built-in reload
  vim.api.nvim_buf_call(bufnr, function()
    vim.cmd("checktime")
  end)
end

--- Handle a file change event (called after debounce).
---@param filepath string  absolute path that changed
local function on_file_changed(filepath)
  vim.schedule(function()
    state.active[filepath] = vim.uv.now()

    reload_buf(filepath)

    -- place active sign if buffer is open
    local bufnr = find_buf(filepath)
    if bufnr then
      ensure_signs()
      place_sign(bufnr, "SadeActive")

      -- schedule settled transition
      local settle_ms = config.values.heartbeat.settle_ms
      vim.defer_fn(function()
        local last = state.active[filepath]
        if last and (vim.uv.now() - last) >= settle_ms then
          state.active[filepath] = nil
          local b = find_buf(filepath)
          if b then
            clear_sign(b)
          end
        end
      end, settle_ms + 50)
    end
  end)
end

--- Start watching a single file path.
---@param filepath string  absolute path
local function watch_file(filepath)
  if state.watchers[filepath] then
    return
  end

  local handle = vim.uv.new_fs_event()
  if not handle then
    return
  end

  local debounce_ms = config.values.heartbeat.debounce_ms

  handle:start(filepath, {}, function(err, _, events)
    if err then
      return
    end
    if not (events.change or events.rename) then
      return
    end

    -- debounce: reset timer on each event
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

  state.watchers[filepath] = handle
end

--- Start watching a directory recursively for changes.
---@param dir string  absolute path to directory
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

    -- skip .git and .sade directories
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
---@param project_root string  absolute path to project root
function M.start(project_root)
  ensure_signs()
  watch_dir(project_root)
  vim.notify("[sade] heartbeat started")
end

--- Stop all watchers and clear state (silent).
function M.stop_silent()
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
  state.active = {}
  vim.fn.sign_unplace(state.sign_group)
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
