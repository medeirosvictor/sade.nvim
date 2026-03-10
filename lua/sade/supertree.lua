local M = {}

local heartbeat = require("sade.heartbeat")

---@class SuperTreeEntry
---@field type "node"|"file"|"unmapped_header"|"unmapped_file"
---@field id string|nil          node id (for node entries)
---@field label string           display label
---@field description string|nil node description
---@field filepath string|nil    absolute path (for file entries)
---@field rel_path string|nil    relative path (for display)
---@field depth number           indentation level
---@field expanded boolean|nil   expand/collapse state (nodes only)
---@field file_count number|nil  total files in node
---@field active boolean         heartbeat active (spinning)
---@field stale boolean          heartbeat stale (changed but settled)

--- Build sorted list of nodes from the index.
---@param idx SadeIndex
---@return table[] nodes  sorted by label
local function sorted_nodes(idx)
  local list = {}
  for _, node in pairs(idx.nodes) do
    table.insert(list, node)
  end
  table.sort(list, function(a, b)
    return a.label < b.label
  end)
  return list
end

--- Get all project files not mapped to any node.
---@param idx SadeIndex
---@return string[] unmapped  sorted relative paths
local function find_unmapped(idx)
  local mapped = {}
  for filepath, _ in pairs(idx.file_to_nodes) do
    mapped[filepath] = true
  end

  local root = idx.project_root
  local unmapped = {}

  -- walk project files (non-recursive scan of common locations)
  local function scan(dir)
    local handle = vim.uv.fs_scandir(dir)
    if not handle then
      return
    end
    while true do
      local name, typ = vim.uv.fs_scandir_next(handle)
      if not name then
        break
      end
      local full = dir .. "/" .. name
      if name:match("^%.") then
        -- skip dotfiles/dirs
      elseif typ == "directory" then
        if name ~= "node_modules" and name ~= ".git" then
          scan(full)
        end
      elseif typ == "file" then
        if not mapped[full] then
          table.insert(unmapped, full)
        end
      end
    end
  end

  scan(root)
  table.sort(unmapped)
  return unmapped
end

--- Build the flat list of entries for rendering.
---@param idx SadeIndex
---@param expanded_state table<string, boolean>  node_id → expanded
---@return SuperTreeEntry[]
function M.build_entries(idx, expanded_state)
  local entries = {}
  local nodes = sorted_nodes(idx)

  for _, node in ipairs(nodes) do
    local is_expanded = expanded_state[node.id] or false

    -- resolve files for this node
    local resolved = {}
    for filepath, node_ids in pairs(idx.file_to_nodes) do
      for _, nid in ipairs(node_ids) do
        if nid == node.id then
          table.insert(resolved, filepath)
          break
        end
      end
    end
    table.sort(resolved)

    -- check if any file in the node is active or stale
    local node_active = false
    local node_stale = false
    for _, fp in ipairs(resolved) do
      if heartbeat.is_active(fp) then
        node_active = true
      elseif heartbeat.is_stale(fp) then
        node_stale = true
      end
    end

    table.insert(entries, {
      type = "node",
      id = node.id,
      label = node.label,
      description = node.description,
      depth = 0,
      expanded = is_expanded,
      file_count = #resolved,
      active = node_active,
      stale = node_stale and not node_active,
    })

    if is_expanded then
      for _, filepath in ipairs(resolved) do
        local rel = filepath:sub(#idx.project_root + 2)
        local file_active = heartbeat.is_active(filepath)
        table.insert(entries, {
          type = "file",
          filepath = filepath,
          rel_path = rel,
          label = rel,
          depth = 1,
          active = file_active,
          stale = not file_active and heartbeat.is_stale(filepath),
        })
      end
    end
  end

  -- unmapped files
  local unmapped = find_unmapped(idx)
  if #unmapped > 0 then
    table.insert(entries, {
      type = "unmapped_header",
      label = "Unmapped",
      depth = 0,
      expanded = expanded_state["__unmapped__"] or false,
      file_count = #unmapped,
      active = false,
    })

    if expanded_state["__unmapped__"] then
      for _, filepath in ipairs(unmapped) do
        local rel = filepath:sub(#idx.project_root + 2)
        table.insert(entries, {
          type = "unmapped_file",
          filepath = filepath,
          rel_path = rel,
          label = rel,
          depth = 1,
          active = heartbeat.is_active(filepath),
        })
      end
    end
  end

  return entries
end

return M
