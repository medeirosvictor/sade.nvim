local templates = require("sade.templates")
local M = {}

--- Walk up from `start` to find a directory containing `.sade/`.
--- Returns the `.sade/` absolute path, or nil + error message.
---@param start? string  starting directory (defaults to cwd)
---@return string|nil sade_root
---@return string|nil error
function M.find_root(start)
  local dir = start or vim.uv.cwd()
  -- Normalize initial directory
  dir = vim.fs.normalize(dir)
  while dir do
    local sade = dir .. "/.sade"
    local stat = vim.uv.fs_stat(sade)
    if stat and stat.type == "directory" then
      return vim.fs.normalize(sade)
    end
    local parent = vim.fn.fnamemodify(dir, ":h")
    if parent == dir then
      break
    end
    dir = parent
  end
  return nil, "no .sade/ directory found"
end

--- Validate that a `.sade/` directory has the required structure.
--- Creates missing directories if found, otherwise returns error.
---@param sade_root string  absolute path to `.sade/`
---@return boolean ok
---@return string|nil error
function M.validate(sade_root)
  local nodes_dir = sade_root .. "/nodes"
  local stat = vim.uv.fs_stat(nodes_dir)
  if not stat or stat.type ~= "directory" then
    -- Auto-create missing directories instead of erroring
    vim.fn.mkdir(nodes_dir, "p")
    vim.fn.mkdir(sade_root .. "/tmp/logs", "p")
  end

  local skill = sade_root .. "/SKILL.md"
  stat = vim.uv.fs_stat(skill)
  if not stat then
    -- Auto-create missing SKILL.md with simple template
    local f = io.open(skill, "w")
    if f then
      f:write("# Coding Patterns\n\n"
        .. "Describe coding style, constraints, and conventions for this project.\n\n"
        .. "## Node Maintenance\n\n"
        .. "When you create, move, or delete files, update the relevant `.sade/nodes/*.md`\n"
        .. "to keep the architecture description accurate.\n")
      f:close()
    end
  end

  return true
end

--- Append SADE section to an existing AGENTS.md file if not already present.
---@param project_root string
local function append_agents_section(project_root)
  local agents_path = project_root .. "/AGENTS.md"
  local f = io.open(agents_path, "r")
  local existing_content = f and f:read("*a") or ""
  if f then
    f:close()
  end

  -- Check if SADE section already exists
  if existing_content:match("SADE") or existing_content:match("%.sade/") then
    return -- Already has SADE content
  end

  -- Append SADE section
  local sade_section = [[

## SADE

This project uses SADE for architecture management. See `.sade/SKILL.md` for coding patterns.

]]

  local out = io.open(agents_path, "a")
  if out then
    out:write(sade_section)
    out:close()
  end
end

--- Ensure AGENTS.md exists in the project root.
--- Creates a new one if missing, appends SADE section if it exists but lacks SADE.
---@param project_root string
function M.ensure_agents(project_root)
  local agents_path = project_root .. "/AGENTS.md"

  if not vim.uv.fs_stat(agents_path) then
    -- Create new AGENTS.md with template
    local project_name = vim.fn.fnamemodify(project_root, ":t")
    local template = templates.AGENTS_TEMPLATE:gsub("%%PROJECT%%", project_name)
    local f = io.open(agents_path, "w")
    if f then
      f:write(template)
      f:close()
    end
  else
    -- Append SADE section to existing AGENTS.md
    append_agents_section(project_root)
  end
end

--- Scaffold a new .sade/ directory with starter files.
---@param project_root string  absolute path to the project root
---@return string sade_root  absolute path to the created .sade/
function M.scaffold(project_root)
  project_root = vim.fs.normalize(project_root)
  local sade_root = project_root .. "/.sade"
  vim.fn.mkdir(sade_root .. "/nodes", "p")

  local function write_if_missing(path, content)
    if not vim.uv.fs_stat(path) then
      local f = io.open(path, "w")
      if f then
        f:write(content)
        f:close()
      end
    end
  end

  local project_name = vim.fn.fnamemodify(project_root, ":t")

  write_if_missing(sade_root .. "/README.md",
    "# " .. project_name .. "\n\n"
    .. "Describe what this project is and its main goals.\n")

  write_if_missing(sade_root .. "/SKILL.md",
    "# Coding Patterns\n\n"
    .. "Describe coding style, constraints, and conventions for this project.\n\n"
    .. "## Node Maintenance\n\n"
    .. "When you create, move, or delete files, update the relevant `.sade/nodes/*.md` and the architecture.json graph notation.\n"
    .. "to keep the architecture description accurate.\n")

  -- Create or append AGENTS.md
  local agents_path = project_root .. "/AGENTS.md"
  if not vim.uv.fs_stat(agents_path) then
    -- Create new AGENTS.md with template
    local template = templates.AGENTS_TEMPLATE:gsub("%%PROJECT%%", project_name)
    write_if_missing(agents_path, template)
  else
    -- Append SADE section to existing AGENTS.md
    append_agents_section(project_root)
  end

  return vim.fs.normalize(sade_root)
end

--- Load agent config for a project.
---@param sade_root string
---@return string|nil agent_cli
function M.load_agent_config(sade_root)
  local config_file = sade_root .. "/config.lua"
  local f = io.open(config_file, "r")
  if not f then
    return nil
  end
  local content = f:read("*a")
  f:close()

  -- simple parse: look for agent_cli = "value"
  local match = content:match('agent_cli%s*=%s*["\']([^"\']+)["\']')
  return match
end

--- Save agent config for a project.
---@param sade_root string
---@param agent_cli string
function M.save_agent_config(sade_root, agent_cli)
  local config_file = sade_root .. "/config.lua"
  local f = io.open(config_file, "w")
  if not f then
    return
  end
  f:write("-- SADE project config\n")
  f:write("agent_cli = \"" .. agent_cli .. "\"\n")
  f:close()
end

return M
