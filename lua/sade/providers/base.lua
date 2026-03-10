--- Provider interface.
--- Each provider must return a table with these fields:
---
---@class SadeProvider
---@field id string              unique key
---@field name string            display name
---@field cmd string             CLI binary name
---@field check string           version check command
---@field build_cmd fun(ctx_file: string, prompt: string|nil): string  full shell command to run

local M = {}

--- Validate a provider table has all required fields.
---@param provider SadeProvider
---@return boolean ok
---@return string|nil err
function M.validate(provider)
  for _, field in ipairs({ "id", "name", "cmd", "check", "build_cmd" }) do
    if not provider[field] then
      return false, "provider missing field: " .. field
    end
  end
  return true, nil
end

return M
