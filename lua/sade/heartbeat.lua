local M = {}

local config = require("sade.config")
local spinner = require("sade.spinner")

local SIGN_GROUP = "sade_heartbeat"

---@class HeartbeatState
local state = {
  watchers = {},           -- path → uv_fs_event_t
  timers = {},             -- path → uv_timer_t (debounce)
  active = {},             -- path → timestamp of last change (spinning)
  stale = {},              -- path → true (changed but settled, dim indicator)
  spinner = nil,           -- SadeSpinner instance
  batch = {},              -- files changed in current burst (for bulk notification)
  batch_timer = nil,       -- timer for batching notifications

  -- File read flash tracking (from agent stdout)
  reads_flash = {},        -- path → uv_timer_t (auto-clears after 2s)
  project_root = nil,      -- project root for resolving relative paths
}

--- Transition a file from active → stale (dim persistent indicator).
---@param filepath string
local function settle_file(filepath)
  state.active[filepath] = nil
  state.stale[filepath] = true

  -- stop spinner if no more active files
  if next(state.active) == nil then
    state.spinner:stop()
  end

  -- place stale sign
  state.spinner:place_stale(filepath)
end

--- Clear a read flash for a file.
---@param filepath string
local function clear_read_flash(filepath)
  if state.reads_flash[filepath] then
    state.reads_flash[filepath]:stop()
    state.reads_flash[filepath]:close()
    state.reads_flash[filepath] = nil
  end
end

--- Track a file change for bulk notification.
---@param filepath string
local function track_batch(filepath)
  state.batch[filepath] = true

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
  local bufnr
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) then
      if vim.api.nvim_buf_get_name(buf) == filepath then
        bufnr = buf
        break
      end
    end
  end

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
    -- promote from stale back to active if changed again
    state.stale[filepath] = nil
    state.active[filepath] = vim.uv.now()

    reload_buf(filepath)
    track_batch(filepath)

    state.spinner:start(function()
      return state.active
    end)

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

--- Flash a file as "being read" by the agent for 2 seconds.
--- If the file is already flashing, resets the timer.
---@param filepath string  absolute path
function M.flash_read(filepath)
  -- clear existing timer for this file
  clear_read_flash(filepath)

  -- set new 2s timer
  local timer = vim.uv.new_timer()
  state.reads_flash[filepath] = timer
  timer:start(2000, 0, function()
    timer:stop()
    timer:close()
    vim.schedule(function()
      state.reads_flash[filepath] = nil
    end)
  end)
end

--- Check if a file is currently flashing as "being read".
---@param filepath string  absolute path
---@return boolean
function M.is_reading(filepath)
  return state.reads_flash[filepath] ~= nil
end

--- Parse agent output line for file paths and flash them.
--- Matches common patterns: "Reading file.lua", "cat file.lua", paths with extensions.
---@param line string  a line of agent stdout/stderr
---@param project_root string  absolute path to resolve relative paths
function M.parse_agent_output(line, project_root)
  if not line or line == "" then
    return
  end

  -- Match file paths with common code extensions
  -- Patterns agents typically emit:
  --   "Read lua/sade/heartbeat.lua"
  --   "Reading file: lua/sade/init.lua"
  --   "cat lua/sade/foo.lua"
  --   "grep ... lua/sade/bar.lua"
  --   "/absolute/path/to/file.lua"
  --   "lua/sade/init.lua" (bare path in output)
  local extensions = "lua|js|ts|jsx|tsx|py|rb|rs|go|c|h|cpp|hpp|java|md|toml|yaml|yml|json|sh|vim"
  local pattern = "([%w_%.%-%/]+%.(" .. extensions:gsub("|", "|") .. "))"

  -- Lua patterns can't do alternation, so match any path-like thing with an extension
  for match in line:gmatch("([%w_%./%-]+%.[%a]+)") do
    -- filter: must have a / (not just "init.lua" standalone) or be a known project file
    -- and must end with a code extension
    local ext = match:match("%.([%a]+)$")
    if ext and extensions:find(ext, 1, true) then
      -- resolve to absolute path
      local abs
      if match:sub(1, 1) == "/" then
        abs = match
      else
        abs = project_root .. "/" .. match
      end

      -- only flash if the file actually exists
      local stat = vim.uv.fs_stat(abs)
      if stat and stat.type == "file" then
        M.flash_read(abs)
      end
    end
  end
end

--- Stop all read flash timers.
function M.stop_read_tracking()
  for filepath, _ in pairs(state.reads_flash) do
    clear_read_flash(filepath)
  end
  state.reads_flash = {}
end

--- Start the heartbeat: watch the project root for file changes.
---@param project_root string
function M.start(project_root)
  state.spinner = spinner.Spinner.new()
  state.spinner:ensure_signs()
  watch_dir(project_root)
end

--- Stop all watchers and clear state (silent).
function M.stop_silent()
  if state.spinner then
    state.spinner:stop()
    state.spinner = nil
  end

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

  -- Stop read flash timers
  M.stop_read_tracking()

  state.active = {}
  state.stale = {}
  state.batch = {}
  spinner.Spinner.clear_all()
end

--- Stop all watchers and clear state.
function M.stop()
  M.stop_silent()
  vim.notify("[sade] heartbeat stopped")
end

--- Clear all stale indicators (like acknowledging changes).
function M.clear_stale()
  state.stale = {}
  -- remove stale signs from all buffers
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) then
      local signs = vim.fn.sign_getplaced(buf, { group = SIGN_GROUP })[1]
      if signs then
        for _, s in ipairs(signs.signs) do
          if s.name == "SadeStale" or s.name == "SadeReadStale" then
            vim.fn.sign_unplace(SIGN_GROUP, { buffer = buf, id = s.id })
          end
        end
      end
    end
  end
  vim.notify("[sade] stale indicators cleared")
end

--- Check if a file is currently active (being modified).
---@param filepath string
---@return boolean
function M.is_active(filepath)
  return state.active[filepath] ~= nil
end

--- Check if a file is stale (was changed, now settled).
---@param filepath string
---@return boolean
function M.is_stale(filepath)
  return state.stale[filepath] ~= nil
end

--- Check if a file has any heartbeat state (active, stale, or reading).
---@param filepath string
---@return boolean
function M.is_touched(filepath)
  return state.active[filepath] ~= nil or state.stale[filepath] ~= nil
    or state.reads_flash[filepath] ~= nil
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

--- Get all stale file paths.
---@return string[]
function M.stale_files()
  local files = {}
  for path, _ in pairs(state.stale) do
    table.insert(files, path)
  end
  return files
end

return M
