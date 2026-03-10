local M = {}

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

--- Collect a flat list of project files (relative paths), skipping noise.
---@param project_root string
---@return string[]
local function collect_files(project_root)
  local files = {}
  local skip = { [".git"] = true, [".sade"] = true, ["node_modules"] = true, [".next"] = true, ["dist"] = true, ["build"] = true, ["vendor"] = true, ["__pycache__"] = true }

  local function scan(dir, prefix)
    local handle = vim.uv.fs_scandir(dir)
    if not handle then
      return
    end
    while true do
      local name, typ = vim.uv.fs_scandir_next(handle)
      if not name then
        break
      end
      if not name:match("^%.") or name == ".sade" then
        local rel = prefix == "" and name or (prefix .. "/" .. name)
        if typ == "directory" and not skip[name] then
          scan(dir .. "/" .. name, rel)
        elseif typ == "file" then
          table.insert(files, rel)
        end
      end
    end
  end

  scan(project_root, "")
  table.sort(files)
  return files
end

--- Build the seed prompt.
---@param sade_root string
---@param project_root string
---@return string prompt
function M.build_prompt(sade_root, project_root)
  local parts = {}

  table.insert(parts, [[You are analyzing a codebase to generate architectural node files.

Each node represents one architectural responsibility — a group of files that share a concern.
Nodes are NOT folders. A node groups files by what they do, regardless of where they live.

For each node, create a markdown file with this exact format:

```markdown
# Node Name

Short description of what this node owns and how it works.

## Files
- path/to/file.lua
- path/to/other/**

## Notes
Implementation details, constraints, decisions.
```

Rules:
- Describe what EXISTS. Do not invent architecture that isn't there.
- Every file should belong to at least one node.
- A file can belong to multiple nodes if it genuinely bridges concerns.
- Use glob patterns (e.g. `src/auth/**`) when a whole directory belongs to one node.
- Keep descriptions short and concrete.
- Node filenames should be kebab-case: `auth.md`, `database.md`, `api-routes.md`.

Output each node as a separate markdown code block, prefixed with the filename:

`nodes/example-name.md`
```markdown
# Example Name
...
```]])

  -- project context
  local readme = read_file(sade_root .. "/README.md")
  if readme then
    table.insert(parts, "## Project README (.sade/README.md)\n\n" .. vim.trim(readme))
  end

  local skill = read_file(sade_root .. "/SKILL.md")
  if skill then
    table.insert(parts, "## Coding Patterns (.sade/SKILL.md)\n\n" .. vim.trim(skill))
  end

  -- file listing
  local files = collect_files(project_root)
  table.insert(parts, "## Project Files\n\n```\n" .. table.concat(files, "\n") .. "\n```")

  table.insert(parts, "Now generate the node files for this project.")

  return table.concat(parts, "\n\n---\n\n")
end

--- Run :SadeSeed — build prompt and copy to clipboard.
---@param sade_root string
---@param project_root string
function M.run(sade_root, project_root)
  local prompt = M.build_prompt(sade_root, project_root)

  -- copy to clipboard
  vim.fn.setreg("+", prompt)

  local line_count = select(2, prompt:gsub("\n", "\n")) + 1
  vim.notify(("[sade] seed prompt copied to clipboard (%d lines)\nPaste it into your agent to generate nodes/*.md"):format(line_count))
end

return M
