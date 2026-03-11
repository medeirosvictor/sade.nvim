local M = {}

local SPINNER_FRAMES = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }
local spinner_frame = 1
local spinner_timer = nil

--- Start the statusline spinner refresh.
local function ensure_spinner()
  if spinner_timer then
    return
  end
  spinner_timer = vim.uv.new_timer()
  spinner_timer:start(0, 80, function()
    spinner_frame = (spinner_frame % #SPINNER_FRAMES) + 1
    vim.schedule(function()
      vim.cmd("redrawstatus")
    end)
  end)
end

--- Stop the statusline spinner.
local function stop_spinner()
  if spinner_timer then
    spinner_timer:stop()
    spinner_timer:close()
    spinner_timer = nil
  end
end

--- Lualine component function.
--- Shows: [node_name] with heartbeat indicator
---   active: spinning braille + node name (orange)
---   stale:  ● + node name (dim)
---   clean:  node name only
---@return string
function M.component()
  local ok, sade = pcall(require, "sade")
  if not ok or type(sade) ~= "table" or not sade.state or not sade.state.index then
    return ""
  end

  local heartbeat = require("sade.heartbeat")
  local index = require("sade.index")
  local idx = sade.state.index

  local buf_path = vim.api.nvim_buf_get_name(0)
  if buf_path == "" then
    return ""
  end

  local node_ids = index.query(idx, buf_path)
  if #node_ids == 0 then
    return ""
  end

  local label = table.concat(node_ids, " · ")

  -- check heartbeat state for current file
  if heartbeat.is_active(buf_path) then
    ensure_spinner()
    return SPINNER_FRAMES[spinner_frame] .. " " .. label
  end

  -- check if any file in the node is active
  local any_active = false
  local any_stale = false
  for _, nid in ipairs(node_ids) do
    for filepath, nids in pairs(idx.file_to_nodes) do
      for _, fid in ipairs(nids) do
        if fid == nid then
          if heartbeat.is_active(filepath) then
            any_active = true
          elseif heartbeat.is_stale(filepath) then
            any_stale = true
          end
        end
      end
    end
  end

  if any_active then
    ensure_spinner()
    return SPINNER_FRAMES[spinner_frame] .. " " .. label
  end

  stop_spinner()

  if any_stale then
    return "● " .. label
  end

  return label
end

--- Lualine color function — returns highlight based on state.
---@return table
function M.color()
  local ok, sade = pcall(require, "sade")
  if not ok or type(sade) ~= "table" or not sade.state or not sade.state.index then
    return {}
  end

  local heartbeat = require("sade.heartbeat")
  local index = require("sade.index")
  local idx = sade.state.index

  local buf_path = vim.api.nvim_buf_get_name(0)
  if buf_path == "" then
    return {}
  end

  local node_ids = index.query(idx, buf_path)
  if #node_ids == 0 then
    return {}
  end

  -- check heartbeat state: active > reading > stale
  if heartbeat.is_active(buf_path) then
    return { fg = "#e0af68" } -- warm orange (writing)
  end
  if heartbeat.is_reading(buf_path) then
    return { fg = "#7dcfff" } -- cyan (reading flash)
  end

  for _, nid in ipairs(node_ids) do
    for filepath, nids in pairs(idx.file_to_nodes) do
      for _, fid in ipairs(nids) do
        if fid == nid then
          if heartbeat.is_active(filepath) then
            return { fg = "#e0af68" }
          end
          if heartbeat.is_reading(filepath) then
            return { fg = "#7dcfff" }
          end
        end
      end
    end
  end

  for _, nid in ipairs(node_ids) do
    for filepath, nids in pairs(idx.file_to_nodes) do
      for _, fid in ipairs(nids) do
        if fid == nid then
          if heartbeat.is_stale(filepath) then
            return { fg = "#7aa2f7" } -- dim blue
          end
        end
      end
    end
  end

  return { fg = "#a9b1d6" } -- subtle gray
end

return M
