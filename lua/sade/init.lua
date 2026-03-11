local config = require("sade.config")
local project = require("sade.project")
local parser = require("sade.parser")
local index = require("sade.index")
local heartbeat = require("sade.heartbeat")
local supertree_ui = require("sade.supertree_ui")
local seed = require("sade.seed")
local agent = require("sade.agent")
local upkeep = require("sade.upkeep")
local node_watcher = require("sade.node_watcher")
local sade_ui = require("sade.ui")
local log = require("sade.log")

local M = {}

--- Plugin state (nil until initialized)
---@type { sade_root: string, project_root: string, index: SadeIndex, agent_running?: number }|nil
M.state = nil

---@param opts? table  user config overrides
function M.setup(opts)
  config.setup(opts)

  vim.api.nvim_create_user_command("SadeInit", function()
    M.init()
  end, { desc = "Initialize SADE: find .sade/, parse nodes, build index" })

  vim.api.nvim_create_user_command("SadeTree", function()
    if not M.state then
      vim.notify("[sade] not initialized. Run :SadeInit", vim.log.levels.WARN)
      return
    end
    supertree_ui.toggle(M.state.index)
  end, { desc = "Toggle SADE Super Tree" })

  vim.api.nvim_create_user_command("SadeSeed", function()
    if not M.state then
      vim.notify("[sade] not initialized. Run :SadeInit", vim.log.levels.WARN)
      return
    end
    log.info("SadeSeed command invoked", { sade_root = M.state.sade_root })
    seed.run(M.state.sade_root, M.state.project_root)
  end, { desc = "Generate node definitions from codebase via agent" })

  vim.api.nvim_create_user_command("SadePrompt", function()
    if not M.state then
      vim.notify("[sade] not initialized. Run :SadeInit", vim.log.levels.WARN)
      return
    end

    -- Check if cursor is in the supertree — adapt prompt to node/file context
    local tree_entry = supertree_ui.get_cursor_entry()
    if tree_entry then
      M._prompt_from_tree(tree_entry)
      return
    end

    local visual = require("sade.ops.visual")
    local selection = visual.get_visual_selection()

    if selection then
      -- Visual mode: show input dialog to get prompt, then execute with selection
      local buf_path = vim.api.nvim_buf_get_name(0)
      local idx = M.state.index
      local node_ids = {}
      if buf_path ~= "" then
        node_ids = require("sade.index").query(idx, buf_path)
      end

      local ui = require("sade.ui")
      local prompt_desc = "Query about selected code"
      if #node_ids > 0 then
        prompt_desc = prompt_desc .. " | Nodes: " .. table.concat(node_ids, ", ")
      end

      ui.input("SADE · Prompt (selection)", {
        placeholder = "What do you want? (e.g., 'explain this', 'refactor this')",
        default = "",
        on_submit = function(text)
          log.info("SadePrompt visual invoked", { prompt = text, sade_root = M.state.sade_root })
          visual.run_visual(M.state.sade_root, M.state.index, { prompt = text })
        end,
      })
    else
      -- No selection: open prompt buffer
      M._prompt_buffer()
    end
  end, { desc = "Prompt agent — adapts to tree selection, visual selection, or opens buffer", nargs = "?" })

  vim.api.nvim_create_user_command("SadeSetup", function()
    agent.setup_interactive()
  end, { desc = "Scan for agent CLIs and configure" })

  vim.api.nvim_create_user_command("SadeStop", function()
    log.set_area("init")
    log.info("SadeStop command invoked")
    agent.stop_all()
  end, { desc = "Stop all running agent requests" })

  vim.api.nvim_create_user_command("SadeHelp", function()
    M.help()
  end, { desc = "Show SADE status, commands, and guide" })

  vim.api.nvim_create_user_command("SadeUpkeep", function()
    if not M.state then
      vim.notify("[sade] not initialized. Run :SadeInit", vim.log.levels.WARN)
      return
    end
    log.info("SadeUpkeep command invoked", { sade_root = M.state.sade_root })
    upkeep.run(M.state.sade_root, M.state.project_root, M.state.index)
  end, { desc = "Check architecture health: unmapped files, empty nodes" })

  if config.values.auto_init then
    vim.api.nvim_create_autocmd("VimEnter", {
      callback = function()
        local root = project.find_root()
        if root then
          M.init()
        end
      end,
      once = true,
    })
  end

  -- Keyboard shortcuts (configurable via config.values.shortcuts)
  if config.values.shortcuts.prompt then
    vim.keymap.set("n", config.values.shortcuts.prompt, function()
      vim.cmd("SadePrompt")
    end, { desc = "SADE: Prompt agent" })
  end
end

--- Open the prompt buffer with optional context header.
---@param header? string  context line to prepend
function M._prompt_buffer(header)
  local prompt = require("sade.prompt")

  local default_text = ""
  if header then
    default_text = header .. "\n"
  else
    local buf_path = vim.api.nvim_buf_get_name(0)
    local idx = M.state.index
    local node_ids = {}
    if buf_path ~= "" then
      node_ids = require("sade.index").query(idx, buf_path)
    end

    if #node_ids > 0 then
      default_text = "-- Context: nodes " .. table.concat(node_ids, ", ") .. "\n"
    elseif buf_path ~= "" then
      default_text = "-- Context: " .. buf_path .. " (not mapped to a node)\n"
    else
      default_text = "-- Context: no file open\n"
    end
  end

  prompt.open({
    title = "SADE · Prompt",
    default_text = default_text,
    on_submit = function(text)
      log.info("SadePrompt invoked", { prompt = text, sade_root = M.state.sade_root })
      agent.invoke(M.state.sade_root, M.state.index, { prompt = text })
    end,
    on_cancel = function() end,
  })
end

--- Short-answer system instruction appended to tree prompts.
local TREE_PROMPT_SUFFIX = [[

IMPORTANT: Keep your response concise — 2 short paragraphs maximum.
Add two otaku-style emojis: one at the very beginning and one at the very end of your response.
Do NOT modify any files. Just answer the question.]]

--- Handle SadePrompt when cursor is on a supertree entry.
--- Opens prompt buffer with short-answer instruction, shows response inline in tree.
---@param entry SuperTreeEntry
function M._prompt_from_tree(entry)
  local context_label
  local context_header

  if entry.type == "node" and entry.id then
    context_label = "node " .. entry.id
    context_header = "-- Context: node " .. entry.id
  elseif (entry.type == "file" or entry.type == "unmapped_file") and entry.filepath then
    local rel = entry.rel_path or entry.filepath
    context_label = "file " .. rel
    context_header = "-- Context: file " .. rel
  else
    M._prompt_buffer()
    return
  end

  local prompt_mod = require("sade.prompt")

  prompt_mod.open({
    title = "SADE · Ask (" .. context_label .. ")",
    default_text = context_header .. "\n",
    on_submit = function(text)
      -- Append the short-answer instruction
      local full_prompt = text .. TREE_PROMPT_SUFFIX
      log.info("SadePrompt tree invoked", { prompt = text, context = context_label })

      -- Invoke agent - response will be shown in tree on complete
      agent.invoke(M.state.sade_root, M.state.index, {
        prompt = full_prompt,
        on_complete = function(response)
          -- Use response from callback (includes all agent output)
          if response then
            -- strip escape codes
            response = response:gsub("\27%][^\7]*\7", "")
            response = response:gsub("\27%[[%d;]*[a-zA-Z]", "")
            response = vim.trim(response)
          end
          if not response or response == "" then
            response = "(no response)"
          end
          log.info("Agent complete, showing response", { resp_len = #(response or "") })
          vim.schedule(function()
            supertree_ui.show_response(response, context_label)
          end)
        end,
        on_error = function(err)
          log.info("Agent error", { err = err })
          vim.schedule(function()
            supertree_ui.show_response("Error: " .. (err or "unknown"), context_label)
          end)
        end,
      })
    end,
    on_cancel = function() end,
  })
end

--- Initialize: find or create .sade/, validate, parse nodes, build index, start heartbeat.
function M.init()
  -- stop existing heartbeat if re-initializing
  node_watcher.stop()
  heartbeat.stop_silent()

  local sade_root = project.find_root()
  if not sade_root then
    -- no .sade/ found — scaffold one in cwd
    local cwd = vim.uv.cwd()
    sade_root = project.scaffold(cwd)
    vim.notify(("[sade] created .sade/ in %s\nEdit README.md and SKILL.md, then run :SadeSeed to generate nodes"):format(cwd))
  end

  local ok, verr = project.validate(sade_root)
  if not ok then
    vim.notify("[sade] " .. verr, vim.log.levels.ERROR)
    return
  end

  local project_root = vim.fn.fnamemodify(sade_root, ":h")

  -- Ensure AGENTS.md exists (create or append SADE section)
  project.ensure_agents(project_root)

  local nodes = parser.parse_all(sade_root .. "/nodes")
  local idx = index.build(nodes, project_root)

  -- Initialize logging
  log.init(sade_root)

  M.state = {
    sade_root = sade_root,
    project_root = project_root,
    index = idx,
  }

  log.info("SADE initialized", {
    sade_root = sade_root,
    project_root = project_root,
    node_count = #nodes,
    file_count = vim.tbl_count(idx.file_to_nodes),
  })

  heartbeat.start(project_root)
  node_watcher.start(sade_root, project_root)

  local count = #nodes
  vim.notify(("[sade] initialized — %d node%s loaded, heartbeat on"):format(count, count == 1 and "" or "s"))

  -- Hint about seeding if no nodes exist
  if count == 0 then
    vim.notify("[sade] no nodes found — run :SadeSeed to generate from codebase", vim.log.levels.INFO)
  end

  -- Auto-open Super Tree if configured
  if config.values.tree.auto_open then
    vim.defer_fn(function()
      supertree_ui.toggle(M.state.index)
    end, 100)
  end
end

--- Show combined help: live status + command reference + guide.
function M.help()
  -- Build live status section
  local status_lines = {}
  if M.state then
    local active = heartbeat.active_files()
    local agent_id = agent.get_configured() or "none"
    local provider = agent.get_provider()
    local agent_name = provider and provider.name or agent_id

    table.insert(status_lines, "  sade root       " .. M.state.sade_root)
    table.insert(status_lines, "  project root    " .. M.state.project_root)
    table.insert(status_lines, "  agent           " .. agent_name)
    table.insert(status_lines, "  nodes           " .. vim.tbl_count(M.state.index.nodes))
    table.insert(status_lines, "  indexed files   " .. vim.tbl_count(M.state.index.file_to_nodes))
    table.insert(status_lines, "  active files    " .. #active)

    local buf_path = vim.api.nvim_buf_get_name(0)
    if buf_path ~= "" then
      local node_ids = index.query(M.state.index, buf_path)
      if #node_ids > 0 then
        table.insert(status_lines, "  current nodes   " .. table.concat(node_ids, ", "))
      else
        table.insert(status_lines, "  current file    not mapped to any node")
      end
      if heartbeat.is_active(buf_path) then
        table.insert(status_lines, "  current file    ACTIVE (external modification)")
      end
    end
  else
    table.insert(status_lines, "  not initialized — run :SadeInit")
  end

  local lines = {
    "",
    "  ╭─────────────────────────────────────────────────────────╮",
    "  │                      STATUS                             │",
    "  ╰─────────────────────────────────────────────────────────╯",
    "",
  }
  vim.list_extend(lines, status_lines)
  vim.list_extend(lines, {
    "",
    "  ╭─────────────────────────────────────────────────────────╮",
    "  │                     COMMANDS                            │",
    "  ╰─────────────────────────────────────────────────────────╯",
    "",
    "  :SadeInit              Initialize plugin, parse nodes, start heartbeat",
    "  :SadeSetup             Scan for agent CLIs and configure",
    "  :SadeSeed              Generate nodes from codebase via agent",
    "",
    "  :SadeTree              Toggle the Super Tree sidebar",
    "  :SadePrompt            Prompt agent (adapts to context — see below)",
    "  :SadeStop              Stop all running agent requests",
    "",
    "  :SadeUpkeep            Check architecture health",
    "  :SadeHelp              This panel",
    "",
    "  ╭─────────────────────────────────────────────────────────╮",
    "  │                   PROMPT MODES                          │",
    "  ╰─────────────────────────────────────────────────────────╯",
    "",
    "  :SadePrompt adapts based on where you invoke it:",
    "",
    "    From Super Tree      Context set to highlighted node/file",
    "    Visual selection      Input dialog → runs agent on selection",
    "    Normal mode           Opens prompt buffer, :wq to submit",
    "",
    "  ╭─────────────────────────────────────────────────────────╮",
    "  │                  SUPER TREE KEYS                        │",
    "  ╰─────────────────────────────────────────────────────────╯",
    "",
    "    Enter / o            Expand/collapse node, or open file",
    "    a                    Invoke agent on node or file",
    "    K                    Edit node markdown file",
    "    i                    Improve node (expand description)",
    "    c                    Compact node (simplify/merge)",
    "    R                    Refresh tree",
    "    q                    Close tree",
    "",
    "  ╭─────────────────────────────────────────────────────────╮",
    "  │                    HEARTBEAT                            │",
    "  ╰─────────────────────────────────────────────────────────╯",
    "",
    "    ⠋ ⠙ ⠹ ...           File actively being modified (orange)",
    "    ●                    File was changed, now settled (blue)",
    "",
    "  ╭─────────────────────────────────────────────────────────╮",
    "  │                      ABOUT                              │",
    "  ╰─────────────────────────────────────────────────────────╯",
    "",
    "  SADE = Software Architecture Description Engine",
    "",
    "  Describe your architecture in .sade/nodes/*.md",
    "  Each node is a responsibility, not a folder.",
    "  Nodes are human-maintained, agent-consumed.",
    "",
    "  Press q or Esc to close",
    "",
  })
  sade_ui.popup(lines, { title = "SADE · Help" })
end

return M
