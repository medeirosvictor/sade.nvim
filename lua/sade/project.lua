local M = {}

--- Walk up from `start` to find a directory containing `.sade/`.
--- Returns the `.sade/` absolute path, or nil + error message.
---@param start? string  starting directory (defaults to cwd)
---@return string|nil sade_root
---@return string|nil error
function M.find_root(start)
  local dir = start or vim.uv.cwd()
  while dir do
    local sade = dir .. "/.sade"
    local stat = vim.uv.fs_stat(sade)
    if stat and stat.type == "directory" then
      return sade
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
---@param sade_root string  absolute path to `.sade/`
---@return boolean ok
---@return string|nil error
function M.validate(sade_root)
  local nodes_dir = sade_root .. "/nodes"
  local stat = vim.uv.fs_stat(nodes_dir)
  if not stat or stat.type ~= "directory" then
    return false, ".sade/nodes/ directory missing"
  end

  local skill = sade_root .. "/SKILL.md"
  stat = vim.uv.fs_stat(skill)
  if not stat then
    return false, ".sade/SKILL.md missing"
  end

  return true
end

return M
