local M = {}

---@class SadeLogLevel
---@field DEBUG number
---@field INFO number
---@field WARN number
---@field ERROR number

---@type SadeLogLevel
M.levels = {
  DEBUG = 1,
  INFO = 2,
  WARN = 3,
  ERROR = 4,
}

M.default_level = M.levels.INFO

--- Log file handle
---@type file|nil
M.fh = nil

--- Current log level
---@type number
M.level = M.default_level

--- Log directory path
---@type string|nil
M.log_dir = nil

--- Initialize logging to .sade/logs/nvim/
---@param sade_root string  path to .sade/ directory
function M.init(sade_root)
  M.log_dir = sade_root .. "/logs/nvim"
  vim.fn.mkdir(M.log_dir, "p")

  local log_file = M.log_dir .. "/sade-" .. os.date("%Y-%m-%d") .. ".log"
  M.fh = io.open(log_file, "a")

  if M.fh then
    M.info("sade.nvim logging initialized", { log_file = log_file })
  else
    vim.notify("[sade] failed to open log file: " .. log_file, vim.log.levels.ERROR)
  end
end

--- Set the log level
---@param level number
function M.set_level(level)
  M.level = level
end

--- Format a log entry
---@param level string
---@param msg string
---@param data table|nil
---@return string
local function format_entry(level, msg, data)
  local timestamp = os.date("%Y-%m-%d %H:%M:%S")
  local parts = { string.format("[%s] [%s] %s", timestamp, level, msg) }
  if data then
    for k, v in pairs(data) do
      table.insert(parts, string.format("  %s: %s", k, vim.inspect(v)))
    end
  end
  return table.concat(parts, "\n")
end

--- Write to log file
---@param level string
---@param msg string
---@param data table|nil
local function write(level, msg, data)
  if not M.fh then
    return
  end

  local entry = format_entry(level, msg, data)
  M.fh:write(entry .. "\n")
  M.fh:flush()
end

--- Log a debug message
---@param msg string
---@param data table|nil
function M.debug(msg, data)
  if M.level <= M.levels.DEBUG then
    write("DEBUG", msg, data)
  end
end

--- Log an info message
---@param msg string
---@param data table|nil
function M.info(msg, data)
  if M.level <= M.levels.INFO then
    write("INFO", msg, data)
  end
end

--- Log a warning message
---@param msg string
---@param data table|nil
function M.warn(msg, data)
  if M.level <= M.levels.WARN then
    write("WARN", msg, data)
  end
end

--- Log an error message
---@param msg string
---@param data table|nil
function M.error(msg, data)
  if M.level <= M.levels.ERROR then
    write("ERROR", msg, data)
  end
end

--- Close the log file
function M.close()
  if M.fh then
    M.info("sade.nvim logging closed")
    M.fh:close()
    M.fh = nil
  end
end

--- Get log directory path
---@return string|nil
function M.get_log_dir()
  return M.log_dir
end

return M
