local M = {}

---@class SadeIndex
---@field nodes table<string, table>    node_id → node table
---@field file_to_nodes table<string, string[]>  filepath → list of node ids
---@field project_root string  project root (parent of .sade/)

--- Resolve a glob or literal path to a list of real file paths.
---@param pattern string  glob or literal path
---@param project_root string
---@return string[]
local function resolve_pattern(pattern, project_root)
  -- use vim.fn.glob for expansion
  local full = project_root .. "/" .. pattern
  local matches = vim.fn.glob(full, false, true)
  local results = {}
  for _, m in ipairs(matches) do
    -- only include files, not directories
    local stat = vim.uv.fs_stat(m)
    if stat and stat.type == "file" then
      table.insert(results, m)
    end
  end
  return results
end

--- Build the index from parsed nodes.
---@param nodes table[]  list of parsed node tables (from parser.parse_all)
---@param project_root string  absolute path to project root (parent of .sade/)
---@return SadeIndex
function M.build(nodes, project_root)
  local idx = {
    nodes = {},
    file_to_nodes = {},
    project_root = project_root,
  }

  for _, node in ipairs(nodes) do
    idx.nodes[node.id] = node

    for _, pattern in ipairs(node.files) do
      local paths = resolve_pattern(pattern, project_root)
      for _, path in ipairs(paths) do
        if not idx.file_to_nodes[path] then
          idx.file_to_nodes[path] = {}
        end
        table.insert(idx.file_to_nodes[path], node.id)
      end
    end
  end

  return idx
end

--- Query: given an absolute file path, return node ids that own it.
---@param idx SadeIndex
---@param filepath string  absolute path
---@return string[]  node ids (may be empty)
function M.query(idx, filepath)
  return idx.file_to_nodes[filepath] or {}
end

--- Query: given an absolute file path, return full node tables that own it.
---@param idx SadeIndex
---@param filepath string  absolute path
---@return table[]  node tables
function M.query_nodes(idx, filepath)
  local ids = M.query(idx, filepath)
  local result = {}
  for _, id in ipairs(ids) do
    if idx.nodes[id] then
      table.insert(result, idx.nodes[id])
    end
  end
  return result
end

return M
