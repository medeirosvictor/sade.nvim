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

  -- File read tracking (via lsof)
  reads_active = {},       -- path → timestamp of last read (spinning)
  reads_stale = {},        -- path → true (read but settled, dim indicator)
  read_poll_timer = nil,   -- timer for polling lsof
  read_pid = nil,          -- PID to track reads for
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

--- Transition a file from active read → stale read (dim persistent indicator).
---@param filepath string
local function settle_read(filepath)
  state.reads_active[filepath] = nil
  state.reads_stale[filepath] = true

  -- place stale read sign
  state.spinner:place_read_stale(filepath)
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

--- Get files currently being read by a process using lsof.
---@param pid number Process ID
---@return string[] List of file paths being read
local function get_read_files(pid)
  local files = {}
  local handle = io.popen("lsof -p " .. pid .. " 2>/dev/null")
  if not handle then
    return files
  end

  -- Skip header line
  local header = handle:lines()()

  for line in handle:lines() do
    -- lsof output format: COMMAND PID USER FD TYPE DEVICE SIZE/OFF NODE NAME
    -- Split by whitespace
    local parts = {}
    for part in line:gmatch("%S+") do
      table.insert(parts, part)
    end

    -- FD is typically the 4th column (index 4)
    if #parts >= 5 then
      local fd = parts[4]
      local name = parts[#parts] -- NAME is usually the last column

      -- Files being read have 'r' in the FD column (e.g., "4r", "r")
      if fd and name and (fd:match("^%d+r$") or fd == "r") then
        -- Only track regular files (not pipes, memfs, etc.)
        if name:match("^/") and not name:match("/dev/") then
          table.insert(files, name)
        end
      end
    end
  end
  handle:close()
  return files
end

--- Poll lsof for files being read and update tracking state.
local function poll_reads()
  if not state.read_pid then
    return
  end

  local read_files = get_read_files(state.read_pid)
  local now = vim.uv.now()

  -- Track which reads we've seen this cycle
  local seen = {}

  for _, filepath in ipairs(read_files) do
    seen[filepath] = true

    -- If not already tracked, add as active
    if not state.reads_active[filepath] and not state.reads_stale[filepath] then
      state.reads_active[filepath] = now
      state.spinner:place_read(filepath)

      -- Schedule settle check for this read (5 seconds)
      local settle_ms = 5000
      vim.defer_fn(function()
        local last = state.reads_active[filepath]
        if last and (vim.uv.now() - last) >= settle_ms then
          settle_read(filepath)
        end
      end, settle_ms + 50)
    else
      -- Already tracked, update timestamp to keep it active
      state.reads_active[filepath] = now
    end
  end

  -- Mark files that are no longer being read as stale
  for filepath, _ in pairs(state.reads_active) do
    if not seen[filepath] then
      settle_read(filepath)
    end
  end
end

--- Start tracking file reads for a process PID.
---@param pid number Process ID to track
function M.track_reads(pid)
  if not pid or pid == 0 then
    return
  end

  state.read_pid = pid

  -- Initialize spinner if not already done (heartbeat might not be started)
  if not state.spinner then
    state.spinner = spinner.Spinner.new()
  end

  -- Ensure spinner signs are defined
  state.spinner:ensure_signs()

  -- Stop existing poll timer if any
  if state.read_poll_timer then
    state.read_poll_timer:stop()
    state.read_poll_timer:close()
  end

  -- Poll every 1 second for file reads
  state.read_poll_timer = vim.uv.new_timer()
  state.read_poll_timer:start(1000, 1000, function()
    vim.schedule(poll_reads)
  end)
end

--- Stop tracking file reads.
function M.stop_read_tracking()
  if state.read_poll_timer then
    state.read_poll_timer:stop()
    state.read_poll_timer:close()
    state.read_poll_timer = nil
  end
  state.read_pid = nil
  state.reads_active = {}
  state.reads_stale = {}
end

--- Start the heartbeat: watch the project root for file changes.
---@param project_root string
function M.start(project_root)
  state.spinner = spinner.Spinner.new()
  state.spinner:ensure_signs()
  watch_dir(project_root)
  vim.notify("[sade] heartbeat started")
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

  -- Stop read tracking
  if state.read_poll_timer then
    state.read_poll_timer:stop()
    state.read_poll_timer:close()
    state.read_poll_timer = nil
  end

  state.active = {}
  state.stale = {}
  state.batch = {}
  state.reads_active = {}
  state.reads_stale = {}
  state.read_pid = nil
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
  state.reads_stale = {}
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

--- Check if a file has any heartbeat state (active or stale).
---@param filepath string
---@return boolean
function M.is_touched(filepath)
  return state.active[filepath] ~= nil or state.stale[filepath] ~= nil
    or state.reads_active[filepath] ~= nil or state.reads_stale[filepath] ~= nil
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

--- Check if a file is currently being read.
---@param filepath string
---@return boolean
function M.is_reading(filepath)
  return state.reads_active[filepath] ~= nil
end

--- Check if a file was read but is now stale.
---@param filepath string
---@return boolean
function M.is_read_stale(filepath)
  return state.reads_stale[filepath] ~= nil
end

--- Get all currently active read file paths.
---@return string[]
function M.reading_files()
  local files = {}
  for path, _ in pairs(state.reads_active) do
    table.insert(files, path)
  end
  return files
end

--- Get all stale read file paths.
---@return string[]
function M.stale_read_files()
  local files = {}
  for path, _ in pairs(state.reads_stale) do
    table.insert(files, path)
  end
  return files
end

return M
