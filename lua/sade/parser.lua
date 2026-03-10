local M = {}

--- Parse a single node markdown file.
---@param filepath string  absolute path to the .md file
---@return table|nil node  { id, label, description, files, notes }
---@return string|nil error
function M.parse_file(filepath)
  local f = io.open(filepath, "r")
  if not f then
    return nil, "cannot open " .. filepath
  end
  local content = f:read("*a")
  f:close()

  local basename = vim.fn.fnamemodify(filepath, ":t:r")
  local node = {
    id = basename,
    label = nil,
    description = "",
    files = {},
    notes = "",
  }

  -- extract heading as label
  node.label = content:match("^#%s+(.-)%s*\n") or basename

  -- split into sections by ## headings
  local sections = {}
  local current_key = "_intro"
  local current_lines = {}

  for line in content:gmatch("[^\n]*") do
    local heading = line:match("^##%s+(.-)%s*$")
    if heading then
      sections[current_key] = table.concat(current_lines, "\n")
      current_key = heading:lower()
      current_lines = {}
    else
      table.insert(current_lines, line)
    end
  end
  sections[current_key] = table.concat(current_lines, "\n")

  -- description: everything between the # heading and the first ## heading
  if sections["_intro"] then
    local desc = sections["_intro"]
    -- strip the # heading line itself
    desc = desc:gsub("^#.-\n", "")
    desc = vim.trim(desc)
    node.description = desc
  end

  -- files: list items from ## Files
  if sections["files"] then
    for line in (sections["files"] .. "\n"):gmatch("([^\n]*)\n") do
      local item = line:match("^%s*%-%s+(.+)")
      if item then
        local trimmed = vim.trim(item)
        if trimmed ~= "" then
          table.insert(node.files, trimmed)
        end
      end
    end
  end

  -- notes
  if sections["notes"] then
    node.notes = vim.trim(sections["notes"])
  end

  return node
end

--- Parse all node files in a directory.
---@param nodes_dir string  absolute path to .sade/nodes/
---@return table nodes  list of parsed node tables
function M.parse_all(nodes_dir)
  local nodes = {}
  local handle = vim.uv.fs_scandir(nodes_dir)
  if not handle then
    return nodes
  end
  while true do
    local name, typ = vim.uv.fs_scandir_next(handle)
    if not name then
      break
    end
    if typ == "file" and name:match("%.md$") then
      local node, err = M.parse_file(nodes_dir .. "/" .. name)
      if node then
        table.insert(nodes, node)
      else
        vim.notify("[sade] " .. (err or "unknown parse error"), vim.log.levels.WARN)
      end
    end
  end
  return nodes
end

return M
