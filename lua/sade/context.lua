local M = {}

local index = require("sade.index")

--- Read a file's contents, or return nil.
---@param filepath string
---@return string|nil
local function read_file(filepath)
  local f = io.open(filepath, "r")
  if not f then
    return nil
  end
  local content = f:read("*a")
  f:close()
  return content
end

--- Assemble context for a given file path.
--- Returns a markdown string with: project README, SKILL, and all matching node contracts.
---@param sade_root string   absolute path to .sade/
---@param idx SadeIndex
---@param filepath string    absolute path to the file being worked on
---@return string context
---@return string[] node_ids  nodes that matched
function M.assemble(sade_root, idx, filepath)
  local parts = {}
  local node_ids = index.query(idx, filepath)

  -- project overview
  local readme = read_file(sade_root .. "/README.md")
  if readme then
    table.insert(parts, "# Project Overview\n\n" .. vim.trim(readme))
  end

  -- coding patterns
  local skill = read_file(sade_root .. "/SKILL.md")
  if skill then
    table.insert(parts, "# Coding Patterns\n\n" .. vim.trim(skill))
  end

  -- node contracts
  if #node_ids > 0 then
    for _, nid in ipairs(node_ids) do
      local node_md = read_file(sade_root .. "/nodes/" .. nid .. ".md")
      if node_md then
        table.insert(parts, "# Node: " .. nid .. "\n\n" .. vim.trim(node_md))
      end
    end
  else
    table.insert(parts, "# Note\n\nThis file is not mapped to any architectural node.")
  end

  -- current file path for reference
  local rel = filepath:sub(#idx.project_root + 2)
  table.insert(parts, "# Current File\n\n`" .. rel .. "`")

  return table.concat(parts, "\n\n---\n\n"), node_ids
end

--- Assemble context for the current buffer.
---@param sade_root string
---@param idx SadeIndex
---@return string|nil context
---@return string[] node_ids
function M.assemble_current(sade_root, idx)
  local buf_path = vim.api.nvim_buf_get_name(0)
  if buf_path == "" then
    return nil, {}
  end
  return M.assemble(sade_root, idx, buf_path)
end

--- Assemble context without a specific file (just project overview + skills).
--- Used when no file is open but user still wants to invoke agent.
---@param sade_root string
---@return string context
function M.assemble_minimal(sade_root)
  local parts = {}

  -- project overview
  local readme = read_file(sade_root .. "/README.md")
  if readme then
    table.insert(parts, "# Project Overview\n\n" .. vim.trim(readme))
  end

  -- coding patterns
  local skill = read_file(sade_root .. "/SKILL.md")
  if skill then
    table.insert(parts, "# Coding Patterns\n\n" .. vim.trim(skill))
  end

  table.insert(parts, "# Note\n\nNo file is currently open. Work on the codebase as a whole or specify a file.")

  return table.concat(parts, "\n\n---\n\n")
end

return M
