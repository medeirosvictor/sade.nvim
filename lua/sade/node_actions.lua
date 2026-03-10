local M = {}

local log = require("sade.log")
local prompts = require("sade.prompts")

--- Get the node under cursor in supertree, or current file's node.
---@return string|nil node_id
local function get_current_node()
  -- Try supertree first - access via require
  local ok, supertree_ui = pcall(require, "sade.supertree_ui")
  if ok and supertree_ui.entries and #supertree_ui.entries > 0 then
    -- Get current window's cursor
    local win = vim.api.nvim_get_current_win()
    local cursor = vim.api.nvim_win_get_cursor(win)
    local entry = supertree_ui.entries[cursor[1]]
    if entry and entry.type == "node" and entry.id then
      return entry.id
    end
  end

  -- Fall back to current file's node
  local sade = package.loaded["sade"]
  if not sade or not sade.state or not sade.state.index then
    return nil
  end

  local buf_path = vim.api.nvim_buf_get_name(0)
  if buf_path == "" then
    return nil
  end

  local idx = sade.state.index
  local node_ids = idx.file_to_nodes[buf_path]
  if node_ids and #node_ids > 0 then
    return node_ids[1]
  end

  return nil
end

--- Build prompt for improving a specific node.
---@param sade_root string
---@param node_id string
---@return string prompt
function M.build_improve_prompt(sade_root, node_id)
  local node_path = sade_root .. "/nodes/" .. node_id .. ".md"
  local f = io.open(node_path, "r")
  local content = f and f:read("*a") or "(node file not found)"
  if f then
    f:close()
  end

  local prompt = prompts.improve_node
    :gsub("{node_path}", "nodes/" .. node_id .. ".md")
    :gsub("{node_content}", content)

  return prompt
end

--- Build prompt for compacting a specific node.
---@param sade_root string
---@param node_id string
---@return string prompt
function M.build_compact_prompt(sade_root, node_id)
  local node_path = sade_root .. "/nodes/" .. node_id .. ".md"
  local f = io.open(node_path, "r")
  local content = f and f:read("*a") or "(node file not found)"
  if f then
    f:close()
  end

  local prompt = prompts.compact_node
    :gsub("{node_path}", "nodes/" .. node_id .. ".md")
    :gsub("{node_content}", content)

  return prompt
end

--- Build prompt for unmapping files from a node.
---@param sade_root string
---@param node_id string
---@return string prompt
function M.build_unmap_prompt(sade_root, node_id)
  local idx = require("sade").state.index

  local files = {}
  for filepath, node_ids in pairs(idx.file_to_nodes) do
    for _, nid in ipairs(node_ids) do
      if nid == node_id then
        table.insert(files, filepath)
        break
      end
    end
  end
  table.sort(files)

  local content = ""
  if #files > 0 then
    content = "Current files in this node:\n\n"
    for _, f in ipairs(files) do
      content = content .. "- " .. f .. "\n"
    end
  else
    content = "No files currently mapped to this node."
  end

  return [[Your task is to unmap files from the node `]] .. node_id .. [[`.

]] .. content .. [[

Review the files above and decide which should be unmapped (removed from this node's ## Files section).
A file should be unmapped if:
- It doesn't meaningfully belong to this node's responsibility
- It would be better represented in a different node
- It's dead code or should be deleted

For each file to unmap, just remove it from the node's ## Files section in `.sade/nodes/]] .. node_id .. [[.md`.

If all files should stay, respond with "No files to unmap."

Output any changes as code blocks with the filename.
]]
end

--- Show telescope picker for node actions.
function M.show_actions()
  local sade = package.loaded["sade"]
  if not sade or not sade.state then
    vim.notify("[sade] not initialized. Run :SadeInit", vim.log.levels.WARN)
    return
  end

  local node_id = get_current_node()
  if not node_id then
    vim.notify("[sade] no node selected. Place cursor on a node in Super Tree or open a mapped file", vim.log.levels.WARN)
    return
  end

  local idx = sade.state.index
  local node = idx.nodes[node_id]
  local node_desc = node and node.description or "(no description)"

  local actions = {
    {
      id = "improve",
      label = "improve",
      desc = "Expand description, add notes, clarify responsibilities",
      icon = "✏️ ",
    },
    {
      id = "compact",
      label = "compact",
      desc = "Simplify, merge with similar nodes, reduce verbosity",
      icon = "📦 ",
    },
    {
      id = "unmap",
      label = "unmap",
      desc = "Remove files from this node",
      icon = "🔗 ",
    },
  }

  -- Check if telescope is available
  local telescope_ok, telescope = pcall(require, "telescope")
  if not telescope_ok then
    -- Fallback to vim.ui.select
    local items = {}
    for _, a in ipairs(actions) do
      table.insert(items, {
        label = a.icon .. " " .. a.label .. " - " .. a.desc,
        id = a.id,
      })
    end

    vim.ui.select(items, {
      prompt = "Node: " .. node_id .. "\n" .. node_desc .. "\n\nSelect action:",
    }, function(item)
      if item then
        M.run_action(item.id, node_id)
      end
    end)
    return
  end

  -- Use telescope
  local pickers = require("telescope.pickers")
  local finders = require("telescope.finders")
  local sorters = require("telescope.sorters")
  local actions_telescope = require("telescope.actions")

  local picker = pickers.new({}, {
    prompt_title = "Node: " .. node_id,
    finder = finders.new_table({
      results = actions,
      entry_maker = function(entry)
        return {
          value = entry.id,
          display = entry.icon .. " " .. entry.label .. " - " .. entry.desc,
          ordinal = entry.label,
        }
      end,
    }),
    sorter = sorters.get_generic_fuzzy_sorter(),
    attach_mappings = function(prompt_bufnr, map)
      actions_telescope.select_entry(prompt_bufnr, function(_, sel)
        if sel and sel.value then
          M.run_action(sel.value, node_id)
        end
      end)
      return true
    end,
  })

  picker:find()
end

--- Run an action on a node.
---@param action "improve"|"compact"|"unmap"
---@param node_id string
function M.run_action(action, node_id)
  local sade = package.loaded["sade"]
  if not sade or not sade.state then
    vim.notify("[sade] not initialized", vim.log.levels.WARN)
    return
  end

  local sade_root = sade.state.sade_root

  local prompt
  if action == "improve" then
    prompt = M.build_improve_prompt(sade_root, node_id)
  elseif action == "compact" then
    prompt = M.build_compact_prompt(sade_root, node_id)
  elseif action == "unmap" then
    prompt = M.build_unmap_prompt(sade_root, node_id)
  else
    vim.notify("[sade] unknown action: " .. action, vim.log.levels.ERROR)
    return
  end

  local agent = require("sade.agent")
  local agent_id = agent.get_configured()

  log.info("node action", { action = action, node_id = node_id })

  -- Copy prompt to clipboard
  vim.fn.setreg("+", prompt)

  if agent_id then
    agent.invoke(sade_root, sade.state.index, { prompt = prompt })
    vim.notify(("[sade] Agent running: %s node '%s'"):format(action, node_id))
  else
    vim.notify("[sade] " .. action .. " prompt copied to clipboard\nNo agent configured. Run :SadeAgentSetup to pick one.", vim.log.levels.WARN)
  end
end

return M
