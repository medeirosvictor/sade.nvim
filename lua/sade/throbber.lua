local M = {}

local throb_icons = {
  { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" },
  { "◐", "◓", "◑", "◒" },
  { "⣾", "⣽", "⣻", "⢿", "⡿", "⣟", "⣯", "⣷" },
  { "◰", "◳", "◲", "◱" },
  { "◜", "◠", "◝", "◞", "◡", "◟" },
}

---@class SadeThrobber
---@field state "init" | "throbbing" | "stopped"
---@field start_time number
---@field tick_time number
---@field cb fun(str: string): nil
local Throbber = {}
Throbber.__index = Throbber

--- Create a new throbber
---@param cb fun(str: string): nil  callback with the icon
---@param tick_time number  ms between ticks (default 80)
---@return SadeThrobber
function Throbber.new(cb, tick_time)
  tick_time = tick_time or 80
  return setmetatable({
    state = "init",
    start_time = 0,
    tick_time = tick_time,
    icons = throb_icons[math.random(#throb_icons)],
    cb = cb,
    timer = nil,
  }, Throbber)
end

function Throbber:_run()
  -- Check state FIRST (before doing any work)
  -- This handles the race where stop() was called between scheduling and execution
  if self.state ~= "throbbing" then
    self.timer = nil
    return
  end

  local index = math.floor((vim.uv.now() - self.start_time) / self.tick_time) % #self.icons + 1
  self.cb(self.icons[index])

  -- Check state AGAIN before scheduling next timer (handles race with stop())
  if self.state ~= "throbbing" then
    self.timer = nil
    return
  end

  self.timer = vim.defer_fn(function()
    self:_run()
  end, self.tick_time)
end

--- Start the throbber
function Throbber:start()
  if self.state == "throbbing" then
    return
  end
  self.state = "throbbing"
  self.start_time = vim.uv.now()
  self:_run()
end

--- Stop the throbber
function Throbber:stop()
  -- Set state FIRST to prevent race with pending _run() callbacks
  self.state = "stopped"
  -- Clear timer reference BEFORE stopping to prevent race with new timer creation
  local timer_id = self.timer
  self.timer = nil
  if timer_id then
    pcall(vim.fn.timer_stop, timer_id)
  end
end

---@class SadeThrobber
M.Throbber = Throbber

return M
