local M = {}

local index = require("sade.index")
local seed = require("sade.seed")

--- Scan project files to find those not mapped to any node.
---@param idx SadeIndex
---@param project_root string
---@return string[] unmapped_files
local function find_unmapped(idx, project_root)
  local mapped = {}
  for filepath, _ in pairs(idx.file_to_nodes) do
    mapped[filepath] = true
  end

  local skip = { [".git"] = true, [".sade"] = true, ["node_modules"] = true, [".next"] = true, ["dist"] = true, ["build"] = true, ["vendor"] = true, ["__pycache__"] = true }
  local unmapped = {}

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
      if not name:match("^%.") or name == ".sade" then
        local rel = dir:sub(#project_root + 2)
        local full = rel == "" and name or (rel .. "/" .. name)
        if typ == "directory" and not skip[name] then
          scan(dir .. "/" .. name)
        elseif typ == "file" then
          local full_path = dir .. "/" .. name
          if not mapped[full_path] then
            table.insert(unmapped, full)
          end
        end
      end
    end
  end

  scan(project_root)
  table.sort(unmapped)
  return unmapped
end

--- Check for empty nodes (no files resolved to them).
---@param idx SadeIndex
---@return string[] empty_nodes
local function find_empty_nodes(idx)
  local empty = {}
  for id, node in pairs(idx.nodes) do
    local has_files = false
    for filepath, nids in pairs(idx.file_to_nodes) do
      for _, nid in ipairs(nids) do
        if nid == id then
          has_files = true
          break
        end
      end
      if has_files then
        break
      end
    end
    if not has_files then
      table.insert(empty, id)
    end
  end
  table.sort(empty)
  return empty
end

--- Run the upkeep check and return results.
---@param sade_root string
---@param project_root string
---@param idx SadeIndex
---@return { unmapped: string[], empty_nodes: string[], node_count: number, file_count: number }
function M.check(sade_root, project_root, idx)
  local unmapped = find_unmapped(idx, project_root)
  local empty_nodes = find_empty_nodes(idx)

  return {
    unmapped = unmapped,
    empty_nodes = empty_nodes,
    node_count = vim.tbl_count(idx.nodes),
    file_count = vim.tbl_count(idx.file_to_nodes),
  }
end

--- Build a prompt for refreshing nodes that have issues.
---@param sade_root string
---@param project_root string
---@param idx SadeIndex
---@return string prompt
function M.build_refresh_prompt(sade_root, project_root, idx)
  local results = M.check(sade_root, project_root, idx)
  local parts = {}

  table.insert(parts, [[Your task is to update the architectural node files in `.sade/nodes/` to reflect the current state of the codebase.

Current state: ]] .. results.node_count .. [[ nodes, ]] .. results.file_count .. [[ indexed files.

]])

  -- reference the guiding files
  table.insert(parts, "See `.sade/README.md` for the project overview and `.sade/SKILL.md` for the coding patterns to follow.\n")

  if #results.empty_nodes > 0 then
    table.insert(parts, "## Empty Nodes (no files matched)\n\nThese nodes exist but no files match their patterns:\n\n")
    for _, nid in ipairs(results.empty_nodes) do
      table.insert(parts, "- " .. nid .. ".md")
    end
    table.insert(parts, "\nFix by either removing these nodes or updating their `## Files` globs to match existing files.")
  end

  if #results.unmapped > 0 then
    table.insert(parts, "\n## Unmapped Files\n\nThese files don't belong to any node yet:\n\n```\n")
    for _, f in ipairs(results.unmapped) do
      table.insert(parts, f)
    end
    table.insert(parts, "```\n\nFix by either creating new nodes for these files or adding them to existing nodes in their `## Files` sections.")
  end

  if #results.empty_nodes == 0 and #results.unmapped == 0 then
    table.insert(parts, "## Status\n\nEverything looks good! All files are mapped to nodes and all nodes have files.\n")
  else
    table.insert(parts, "\n## Your Task\n\nUpdate the `.sade/nodes/*.md` files to fix the issues above. Be specific about which files belong to which nodes.")
  end

  return table.concat(parts, "\n")
end

--- Run upkeep check and show results.
---@param sade_root string
---@param project_root string
---@param idx SadeIndex
function M.run(sade_root, project_root, idx)
  local results = M.check(sade_root, project_root, idx)

  local lines = { "", "  SADE Upkeep Check", string.rep("─", 40) }

  table.insert(lines, "")
  table.insert(lines, "  Nodes: " .. results.node_count .. "  |  Indexed files: " .. results.file_count)

  if #results.empty_nodes > 0 then
    table.insert(lines, "")
    table.insert(lines, "  ⚠ Empty nodes (no matching files):")
    for _, nid in ipairs(results.empty_nodes) do
      table.insert(lines, "    - " .. nid)
    end
  end

  if #results.unmapped > 0 then
    table.insert(lines, "")
    table.insert(lines, "  ⚠ Unmapped files (not in any node):")
    -- show first 20, truncate if many
    local limit = 20
    for i, f in ipairs(results.unmapped) do
      if i <= limit then
        table.insert(lines, "    - " .. f)
      end
    end
    if #results.unmapped > limit then
      table.insert(lines, "    ... and " .. (#results.unmapped - limit) .. " more")
    end
  end

  local has_nodes = results.node_count > 0

  if #results.empty_nodes == 0 and #results.unmapped == 0 then
    table.insert(lines, "")
    table.insert(lines, "  ✓ All files mapped, all nodes populated")
  end

  table.insert(lines, "")

  if not has_nodes then
    table.insert(lines, "  No nodes found. Press 'r' to generate initial nodes.")
  else
    table.insert(lines, "  Press 'r' to run agent (or copy to clipboard if no agent)")
  end
  table.insert(lines, "  Press 'R' to rebuild the index")
  table.insert(lines, "  Press q or Esc to close")

  local ui = require("sade.ui")
  local buf, win = ui.popup(lines, { title = "SADE · Upkeep" })

  -- helper to rebuild index and refresh tree
  local function rebuild_and_refresh()
    local parser = require("sade.parser")
    local nodes = parser.parse_all(sade_root .. "/nodes")
    local new_idx = index.build(nodes, project_root)
    local sade = require("sade")
    sade.state.index = new_idx
    vim.notify(("[sade] index rebuilt — %d nodes, %d files"):format(vim.tbl_count(new_idx.nodes), vim.tbl_count(new_idx.file_to_nodes)))

    -- refresh super tree if open
    local supertree = require("sade.supertree_ui")
    if supertree and supertree.refresh then
      supertree.refresh()
    end
  end

  vim.keymap.set("n", "r", function()
    vim.api.nvim_win_close(win, true)

    -- check if agent is configured
    local agent = require("sade.agent")
    local agent_id = agent.get_configured()

    if not has_nodes then
      -- fresh project: run seed flow
      local seed = require("sade.seed")
      local prompt = seed.build_prompt(sade_root, project_root)
      vim.fn.setreg("+", prompt)

      if agent_id then
        -- invoke agent - after it finishes, rebuild index
        -- we can't easily hook into agent completion, so we'll notify user to run :SadeUpkeep again
        agent.invoke(sade_root, nil, { prompt = prompt })
        vim.notify("[sade] After the agent saves nodes, run :SadeUpkeep or press R to rebuild the index")
      else
        vim.notify("[sade] seed prompt copied to clipboard\nNo agent configured. Run :SadeAgentSetup to pick one.", vim.log.levels.WARN)
      end
      return
    end

    -- existing nodes: run upkeep flow
    local prompt = M.build_refresh_prompt(sade_root, project_root, idx)
    vim.fn.setreg("+", prompt)

    if agent_id then
      agent.invoke(sade_root, idx, { prompt = "Maintain the architectural nodes. " .. prompt })
      vim.notify("[sade] After the agent saves changes, run :SadeUpkeep or press R to rebuild the index")
    else
      vim.notify("[sade] refresh prompt copied to clipboard\nNo agent configured. Run :SadeAgentSetup to pick one.", vim.log.levels.WARN)
    end
  end, { buffer = buf, silent = true })

  vim.keymap.set("n", "R", function()
    vim.api.nvim_win_close(win, true)
    rebuild_and_refresh()
  end, { buffer = buf, silent = true })
end

return M
