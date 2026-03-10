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

  table.insert(parts, [[Your task is to describe the architecture of this codebase by creating node files.

Each node represents one architectural responsibility — a group of files that work together toward a shared purpose.
Nodes are NOT folders. A node groups files by what they DO, not where they live.

Create one markdown file per node in `.sade/nodes/` with this format:

```markdown
# Node Name

Brief description of what this node owns and how it works.

## Files
- path/to/file.lua
- path/to/other/**

## Notes
Any implementation details, constraints, or decisions worth documenting.
```

Guidelines:
- Describe what EXISTS in the codebase. Don't invent architecture that isn't there.
- Every source file should belong to at least one node.
- A file can belong to multiple nodes if it genuinely bridges concerns.
- Use glob patterns (e.g. `src/auth/**`) when a whole directory belongs to one node.
- Keep descriptions concise and concrete.
- Name node files in kebab-case: `auth.md`, `database.md`, `api-routes.md`.

Output each node as a code block prefixed with its filename:

`nodes/auth.md`
```markdown
# Auth
...
```
]])

  -- reference the project files
  local readme = read_file(sade_root .. "/README.md")
  if readme then
    table.insert(parts, "## Project Overview\n\nSee `.sade/README.md` for context on what this project is and its goals.")
  end

  local skill = read_file(sade_root .. "/SKILL.md")
  if skill then
    table.insert(parts, "## Coding Patterns\n\nSee `.sade/SKILL.md` for the coding style and conventions to follow.")
  end

  -- file listing
  local files = collect_files(project_root)
  table.insert(parts, "## All Project Files\n\n```\n" .. table.concat(files, "\n") .. "\n```")

  table.insert(parts, "Create the node files now. Start with the files you understand best, then work through the rest.")

  return table.concat(parts, "\n\n---\n\n")
end

--- Run :SadeSeed — build prompt, copy to clipboard, optionally invoke agent.
---@param sade_root string
---@param project_root string
function M.run(sade_root, project_root)
  local prompt = M.build_prompt(sade_root, project_root)

  -- copy to clipboard
  vim.fn.setreg("+", prompt)

  -- check if agent is configured
  local agent = require("sade.agent")
  local agent_id = agent.get_configured()

  local line_count = select(2, prompt:gsub("\n", "\n")) + 1

  if agent_id then
    -- invoke agent directly
    agent.invoke(sade_root, nil, { prompt = prompt })
  else
    -- no agent configured
    vim.notify(("[sade] seed prompt copied to clipboard (%d lines)\nNo agent configured. Run :SadeAgentSetup to pick one, then paste into your agent."):format(line_count), vim.log.levels.WARN)
  end
end

return M
