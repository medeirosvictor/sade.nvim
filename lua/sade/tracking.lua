local M = {}

---@class SadeRequest
---@field id number
---@field cmd string
---@field provider string
---@field started_at number
---@field state "requesting" | "success" | "failed" | "cancelled"
---@field job_id number
---@field proc vim.SystemObj?

local Request = {}
Request.__index = Request

---@class SadeTracking
---@field requests SadeRequest[]
---@field id_counter number
local Tracking = {}
Tracking.__index = Tracking

function Tracking.new()
  return setmetatable({
    requests = {},
    id_counter = 0,
  }, Tracking)
end

--- Generate a unique ID
---@return number
function Tracking:_gen_id()
  self.id_counter = self.id_counter + 1
  return self.id_counter
end

--- Track a new request
---@param cmd string
---@param provider string
---@return SadeRequest
function Tracking:track(cmd, provider)
  local request = setmetatable({
    id = self:_gen_id(),
    cmd = cmd,
    provider = provider,
    started_at = vim.uv.now(),
    state = "requesting",
    job_id = nil,
    proc = nil,
  }, Request)

  table.insert(self.requests, request)
  return request
end

--- Get request by ID
---@param id number
---@return SadeRequest|nil
function Tracking:get(id)
  for _, req in ipairs(self.requests) do
    if req.id == id then
      return req
    end
  end
  return nil
end

--- Get active requests
---@return SadeRequest[]
function Tracking:active()
  local active = {}
  for _, req in ipairs(self.requests) do
    if req.state == "requesting" then
      table.insert(active, req)
    end
  end
  return active
end

--- Get active count
---@return number
function Tracking:active_count()
  local count = 0
  for _, req in ipairs(self.requests) do
    if req.state == "requesting" then
      count = count + 1
    end
  end
  return count
end

--- Complete a request
---@param id number
---@param status "success" | "failed" | "cancelled"
function Tracking:complete(id, status)
  local req = self:get(id)
  if req then
    req.state = status
  end
end

--- Stop all active requests
function Tracking:stop_all()
  for _, req in ipairs(self:active()) do
    req.state = "cancelled"
    if req.proc then
      pcall(function()
        req.proc:kill(15) -- SIGTERM
      end)
    end
  end
end

--- Clear completed requests (keep only requesting)
function Tracking:clear()
  local keep = {}
  for _, req in ipairs(self.requests) do
    if req.state == "requesting" then
      table.insert(keep, req)
    end
  end
  self.requests = keep
end

M.Tracking = Tracking

return M
