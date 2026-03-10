local M = {}

local log = require("sade.log")
local prompts = require("sade.prompts")

--- Get the current entry from supertree (node or file).
---@return table|nil entry, string|nil context ("node" or "file" or "unmapped")
local function get_current_entry()
  local ok, supertree_ui = pcall(require, "sade.supertree_ui")
  if ok and supertree_ui.entries and #supertree_ui.entries > 0 then
    local win = vim.api.nvim_get_current_win()
    local cursor = vim.api.nvim_win_get_cursor(win)
    local entry = supertree_ui.entries[cursor[1]]
    if entry then
      if entry.type == "node" then
        return entry, "node"
      elseif entry.type == "file" then
        return entry, "file"
      elseif entry.type == "unmapped_file" then
        return entry, "unmapped"
      end
    end
  end
  return nil, nil
end

--- Get node files.
---@param sade_root string
---@param node_id string
---@return string[]
local function get_node_files(sade_root, node_id)
  local sade = package.loaded["sade"]
  if not sade or not sade.state or not sade.state.index then
    return {}
  end

  local idx = sade.state.index
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
  return files
end

--- Get all node summaries for prompts.
---@return string
local function get_node_summaries()
  local sade = package.loaded["sade"]
  if not sade or not sade.state or not sade.state.index then
    return "No nodes defined."
  end

  local idx = sade.state.index
  local summaries = {}

  for node_id, node in pairs(idx.nodes) do
    local file_count = 0
    for _, node_ids in pairs(idx.file_to_nodes) do
      for _, nid in ipairs(node_ids) do
        if nid == node_id then
          file_count = file_count + 1
          break
        end
      end
    end

    local desc = node.description or "(no description)"
    table.insert(summaries, string.format("### %s\n%s\nFiles: %d", node_id, desc, file_count))
  end

  table.sort(summaries)
  return table.concat(summaries, "\n\n")
end

--- Read file content (truncated for prompts).
---@param filepath string
---@param max_lines number
---@return string
local function read_file_content(filepath, max_lines)
  local f = io.open(filepath, "r")
  if not f then
    return "(file not readable)"
  end

  local lines = {}
  local count = 0
  for line in f:lines() do
    count = count + 1
    if count <= max_lines then
      table.insert(lines, line)
    else
      break
    end
  end
  f:close()

  if count > max_lines then
    table.insert(lines, "... (truncated, " .. (count - max_lines) .. " more lines)")
  end

  return table.concat(lines, "\n")
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

  return prompts.improve_node
    :gsub("{node_path}", "nodes/" .. node_id .. ".md")
    :gsub("{node_content}", content)
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

  return prompts.compact_node
    :gsub("{node_path}", "nodes/" .. node_id .. ".md")
    :gsub("{node_content}", content)
end

--- Build prompt for unmapping files from a node.
---@param sade_root string
---@param node_id string
---@return string prompt
function M.build_unmap_prompt(sade_root, node_id)
  local files = get_node_files(sade_root, node_id)

  local content = ""
  if #files > 0 then
    content = "Current files in this node:\n\n"
    for _, f in ipairs(files) do
      content = content .. "- " .. f .. "\n"
    end
  else
    content = "No files currently mapped to this node."
  end

  return prompts.unmap_node
    :gsub("{node_path}", "nodes/" .. node_id .. ".md")
    :gsub("{files_to_unmap}", content)
    :gsub("{node_content}", content)
end

--- Build prompt for analyzing a file.
---@param sade_root string
---@param filepath string
---@return string prompt
function M.build_analyze_prompt(sade_root, filepath)
  local file_content = read_file_content(filepath, 200)
  local node_summaries = get_node_summaries()

  -- Get current nodes for this file
  local sade = package.loaded["sade"]
  local current_nodes = "none"
  if sade and sade.state and sade.state.index then
    local node_ids = sade.state.index.file_to_nodes[filepath]
    if node_ids and #node_ids > 0 then
      current_nodes = table.concat(node_ids, ", ")
    end
  end

  return prompts.analyze_file
    :gsub("{file_path}", filepath)
    :gsub("{file_content}", file_content)
    :gsub("{node_summaries}", node_summaries)
    :gsub("{current_nodes}", current_nodes)
end

--- Build prompt for reclassifying a file.
---@param sade_root string
---@param filepath string
---@return string prompt
function M.build_reclassify_prompt(sade_root, filepath)
  local file_content = read_file_content(filepath, 200)
  local node_summaries = get_node_summaries()

  -- Get current nodes for this file
  local sade = package.loaded["sade"]
  local current_nodes = "none"
  if sade and sade.state and sade.state.index then
    local node_ids = sade.state.index.file_to_nodes[filepath]
    if node_ids and #node_ids > 0 then
      current_nodes = table.concat(node_ids, ", ")
    end
  end

  return prompts.reclassify_file
    :gsub("{file_path}", filepath)
    :gsub("{file_content}", file_content)
    :gsub("{node_summaries}", node_summaries)
    :gsub("{current_nodes}", current_nodes)
end

--- Build prompt for evaluating architecture health.
---@return string prompt
function M.build_evaluate_prompt()
  local sade = package.loaded["sade"]
  if not sade or not sade.state or not sade.state.index then
    return prompts.evaluate
  end

  local idx = sade.state.index
  local node_count = vim.tbl_count(idx.nodes)
  local file_count = vim.tbl_count(idx.file_to_nodes)

  -- Count unmapped files
  local mapped = {}
  for fp, _ in pairs(idx.file_to_nodes) do
    mapped[fp] = true
  end

  local project_root = sade.state.project_root
  local unmapped_count = 0
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
      if name:match("^%.") then
        -- skip dotfiles
      elseif typ == "directory" and name ~= "node_modules" and name ~= ".git" then
        scan(dir .. "/" .. name)
      elseif typ == "file" then
        local full = dir .. "/" .. name
        if not mapped[full] then
          unmapped_count = unmapped_count + 1
        end
      end
    end
  end
  scan(project_root)

  return prompts.evaluate
    :gsub("{node_count}", tostring(node_count))
    :gsub("{file_count}", tostring(file_count))
    :gsub("{unmapped_count}", tostring(unmapped_count))
end

--- Run an action on a node or file.
---@param action string
---@param target_id string|nil (node_id or filepath)
---@param target_type string|nil ("node" or "file")
function M.run_action(action, target_id, target_type)
  local sade = package.loaded["sade"]
  if not sade or not sade.state then
    vim.notify("[sade] not initialized", vim.log.levels.WARN)
    return
  end

  local sade_root = sade.state.sade_root

  local prompt
  if action == "improve" then
    prompt = M.build_improve_prompt(sade_root, target_id)
  elseif action == "compact" then
    prompt = M.build_compact_prompt(sade_root, target_id)
  elseif action == "unmap" then
    prompt = M.build_unmap_prompt(sade_root, target_id)
  elseif action == "analyze" then
    prompt = M.build_analyze_prompt(sade_root, target_id)
  elseif action == "reclassify" then
    prompt = M.build_reclassify_prompt(sade_root, target_id)
  elseif action == "evaluate" then
    prompt = M.build_evaluate_prompt()
  else
    vim.notify("[sade] unknown action: " .. action, vim.log.levels.ERROR)
    return
  end

  local agent = require("sade.agent")
  local agent_id = agent.get_configured()

  log.info("sade action", { action = action, target = target_id, type = target_type })

  -- Copy prompt to clipboard
  vim.fn.setreg("+", prompt)

  if agent_id then
    agent.invoke(sade_root, sade.state.index, { prompt = prompt })
    local desc = target_type and (target_type .. " " .. target_id) or target_id
    vim.notify(("[sade] Agent running: %s on '%s'"):format(action, desc or "architecture"))
  else
    vim.notify("[sade] " .. action .. " prompt copied to clipboard\nNo agent configured. Run :SadeAgentSetup to pick one.", vim.log.levels.WARN)
  end
end

--- Show the main Sade actions menu.
function M.show_actions()
  local sade = package.loaded["sade"]
  if not sade or not sade.state then
    vim.notify("[sade] not initialized. Run :SadeInit", vim.log.levels.WARN)
    return
  end

  -- Get current entry from supertree
  local entry, context = get_current_entry()

  -- Determine available actions based on context
  local actions = {}

  if context == "node" and entry then
    -- Node actions
    actions = {
      { id = "improve", label = "improve", desc = "Expand description, clarify responsibilities", icon = "✏️ ", key = "i" },
      { id = "compact", label = "compact", desc = "Simplify, merge with similar nodes", icon = "📦 ", key = "c" },
      { id = "unmap", label = "unmap", desc = "Remove files from this node", icon = "🔗 ", key = "u" },
    }
  elseif context == "file" or context == "unmapped" then
    -- File actions
    local filepath = entry and entry.filepath
    if filepath then
      actions = {
        { id = "analyze", label = "analyze", desc = "Evaluate which node this file belongs to", icon = "🔍 ", key = "a" },
        { id = "reclassify", label = "reclassify", desc = "Move file to different node(s)", icon = "📤 ", key = "r" },
      }
    end
  end

  -- Always add evaluate action
  table.insert(actions, { id = "evaluate", label = "evaluate", desc = "Assess overall architecture health", icon = "📊 ", key = "e" })

  -- Build description based on context
  local title = "SADE"
  local node_desc = ""
  local files_list = ""

  if context == "node" and entry then
    local idx = sade.state.index
    local node = idx.nodes[entry.id]
    node_desc = node and node.description or "(no description)"

    local files = get_node_files(sade.state.sade_root, entry.id)
    if #files > 0 then
      files_list = "\n\nFiles in this node:\n" .. table.concat(files, "\n")
    else
      files_list = "\n\n(no files mapped)"
    end

    title = "Node: " .. entry.id
  elseif context == "file" and entry then
    title = "File: " .. (entry.rel_path or entry.filepath)
    -- Find which nodes this file belongs to
    local idx = sade.state.index
    local node_ids = idx.file_to_nodes[entry.filepath]
    if node_ids and #node_ids > 0 then
      node_desc = "Currently in: " .. table.concat(node_ids, ", ")
    else
      node_desc = "Not mapped to any node"
    end
  elseif context == "unmapped" and entry then
    title = "File: " .. (entry.rel_path or entry.filepath)
    node_desc = "Unmapped (not in any node)"
  else
    node_desc = "No selection - select a node or file in Super Tree, or open a mapped file"
  end

  -- Check if telescope is available
  local telescope_ok, _ = pcall(require, "telescope")
  if not telescope_ok then
    -- Fallback to vim.ui.select
    local items = {}
    for _, a in ipairs(actions) do
      table.insert(items, {
        label = a.icon .. " " .. a.label .. " - " .. a.desc .. " (" .. a.key .. ")",
        id = a.id,
      })
    end

    vim.ui.select(items, {
      prompt = title .. "\n" .. node_desc .. files_list .. "\n\nSelect action:",
    }, function(item)
      if item then
        local target_id = entry and (entry.id or entry.filepath)
        M.run_action(item.id, target_id, context)
      end
    end)
    return
  end

  -- Use telescope with enhanced display
  local pickers = require("telescope.pickers")
  local finders = require("telescope.finders")
  local sorters = require("telescope.sorters")
  local action_state = require("telescope.actions.state")

  local picker = pickers.new({}, {
    prompt_title = title,
    results_title = node_desc .. files_list,
    finder = finders.new_table({
      results = actions,
      entry_maker = function(a)
        return {
          value = a.id,
          display = a.icon .. " " .. a.label .. " - " .. a.desc,
          ordinal = a.label,
        }
      end,
    }),
    sorter = sorters.get_generic_fuzzy_sorter(),
    attach_mappings = function(prompt_bufnr, map)
      -- Run action on selection
      local function run_sel()
        local selection = action_state.get_selected_entry()
        if selection and selection.value then
          local target_id = entry and (entry.id or entry.filepath)
          M.run_action(selection.value, target_id, context)
        end
      end

      -- Keybindings
      map("i", "<CR>", run_sel)
      map("n", "<CR>", run_sel)

      -- Also allow number keys for quick selection
      for i, a in ipairs(actions) do
        if a.key then
          map("i", tostring(i), function()
            action_state.select_default(prompt_bufnr)
          end)
        end
      end

      return true
    end,
  })

  picker:find()
end

return M
