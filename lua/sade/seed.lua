local M = {}

local log = require("sade.log")

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

--- Get modification times for node files.
---@param sade_root string
---@return table<string, number>
local function get_node_mtimes(sade_root)
  local nodes_dir = sade_root .. "/nodes"
  local times = {}

  local handle = vim.uv.fs_scandir(nodes_dir)
  if not handle then
    return times
  end

  while true do
    local name, typ = vim.uv.fs_scandir_next(handle)
    if not name then
      break
    end
    if typ == "file" and name:match("%.md$") then
      local path = nodes_dir .. "/" .. name
      local stat = vim.uv.fs_stat(path)
      if stat then
        times[(name:gsub("%.md$", ""))] = stat.mtime
      end
    end
  end

  return times
end

--- Format a timestamp for display.
---@param ts number|nil
---@return string
local function format_time(ts)
  if not ts then
    return "N/A"
  end

  local ok, sec = pcall(function()
    return os.date("%s", ts)
  end)
  if not ok or not sec then
    return "N/A"
  end

  local diff = os.time() - tonumber(sec)
  if diff < 60 then
    return "just now"
  elseif diff < 3600 then
    local mins = math.floor(diff / 60)
    return mins .. " min" .. (mins == 1 and "" or "s") .. " ago"
  elseif diff < 86400 then
    local hours = math.floor(diff / 3600)
    return hours .. " hour" .. (hours == 1 and "" or "s") .. " ago"
  else
    return os.date("%Y-%m-%d", ts)
  end
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

--- Run :SadeSeed — show modal with status, allow seeding.
---@param sade_root string
---@param project_root string
function M.run(sade_root, project_root)
  log.info("seed.run called", { sade_root = sade_root, project_root = project_root })

  local nodes = {}
  local handle = vim.uv.fs_scandir(sade_root .. "/nodes")
  log.debug("scanning nodes dir", { path = sade_root .. "/nodes", handle = handle ~= nil })
  if handle then
    while true do
      local name = vim.uv.fs_scandir_next(handle)
      if not name then
        break
      end
      if name:match("%.md$") then
        table.insert(nodes, (name:gsub("%.md$", "")))
      end
    end
  end
  table.sort(nodes)

  local mtimes = get_node_mtimes(sade_root)

  local has_nodes = #nodes > 0

  local lines = { "", "  SADE · Seed", string.rep("─", 40) }

  if has_nodes then
    table.insert(lines, "")
    table.insert(lines, "  Current nodes: " .. #nodes)
    table.insert(lines, "")
    table.insert(lines, "  Last modified:")
    for _, n in ipairs(nodes) do
      table.insert(lines, "    • " .. n .. ": " .. format_time(mtimes[n]))
    end
    table.insert(lines, "")
    table.insert(lines, "  Press 'r' to regenerate nodes (agent will overwrite)")
    table.insert(lines, "  Press 'R' to just copy the seed prompt to clipboard")
  else
    table.insert(lines, "")
    table.insert(lines, "  No nodes found.")
    table.insert(lines, "")
    table.insert(lines, "  Press 'r' to generate initial nodes with your agent")
    table.insert(lines, "  Press 'R' to copy seed prompt to clipboard")
  end

  table.insert(lines, "")
  table.insert(lines, "  Press q or Esc to close")

  local ui = require("sade.ui")
  local buf, win = ui.popup(lines, { title = "SADE · Seed" })

  vim.keymap.set("n", "r", function()
    vim.api.nvim_win_close(win, true)

    local prompt = M.build_prompt(sade_root, project_root)
    vim.fn.setreg("+", prompt)

    local agent = require("sade.agent")
    local agent_id = agent.get_configured()

    log.info("seed: 'r' pressed, invoking agent", { agent_id = agent_id, prompt_len = #prompt })

    if agent_id then
      agent.invoke(sade_root, nil, { prompt = prompt })
      vim.notify("[sade] After the agent saves nodes, run :SadeUpkeep or press R to rebuild the index")
    else
      log.warn("seed: no agent configured")
      vim.notify("[sade] seed prompt copied to clipboard\nNo agent configured. Run :SadeAgentSetup to pick one.", vim.log.levels.WARN)
    end
  end, { buffer = buf, silent = true })

  vim.keymap.set("n", "R", function()
    vim.api.nvim_win_close(win, true)

    local prompt = M.build_prompt(sade_root, project_root)
    vim.fn.setreg("+", prompt)
    local line_count = select(2, prompt:gsub("\n", "\n")) + 1
    vim.notify(("[sade] seed prompt copied to clipboard (%d lines)"):format(line_count))
  end, { buffer = buf, silent = true })
end

return M
