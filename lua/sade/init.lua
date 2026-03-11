local config = require("sade.config")
local project = require("sade.project")
local parser = require("sade.parser")
local index = require("sade.index")
local heartbeat = require("sade.heartbeat")
local supertree_ui = require("sade.supertree_ui")
local context = require("sade.context")
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

  vim.api.nvim_create_user_command("SadeInfo", function()
    M.info()
  end, { desc = "Show SADE status and current file's node" })

  vim.api.nvim_create_user_command("SadeTree", function()
    if not M.state then
      vim.notify("[sade] not initialized. Run :SadeInit", vim.log.levels.WARN)
      return
    end
    supertree_ui.toggle(M.state.index)
  end, { desc = "Toggle SADE Super Tree" })

  vim.api.nvim_create_user_command("SadeContext", function()
    if not M.state then
      vim.notify("[sade] not initialized. Run :SadeInit", vim.log.levels.WARN)
      return
    end
    local ctx, node_ids = context.assemble_current(M.state.sade_root, M.state.index)
    if not ctx then
      vim.notify("[sade] no file open", vim.log.levels.WARN)
      return
    end
    vim.fn.setreg("+", ctx)
    local nodes_str = #node_ids > 0 and table.concat(node_ids, ", ") or "none"
    vim.notify(("[sade] context copied to clipboard (nodes: %s)"):format(nodes_str))
  end, { desc = "Copy current file's SADE context to clipboard" })

  vim.api.nvim_create_user_command("SadeSeed", function()
    if not M.state then
      vim.notify("[sade] not initialized. Run :SadeInit", vim.log.levels.WARN)
      return
    end
    log.info("SadeSeed command invoked", { sade_root = M.state.sade_root })
    seed.run(M.state.sade_root, M.state.project_root)
  end, { desc = "Show seed modal with node status and seeding options" })

  vim.api.nvim_create_user_command("SadeAgent", function()
    if not M.state then
      vim.notify("[sade] not initialized. Run :SadeInit", vim.log.levels.WARN)
      return
    end

    -- Get current file info for context
    local buf_path = vim.api.nvim_buf_get_name(0)
    local idx = M.state.index
    local node_ids = {}
    if buf_path ~= "" then
      node_ids = require("sade.index").query(idx, buf_path)
    end

    -- Show input dialog for prompt
    local ui = require("sade.ui")
    local prompt_title = "SADE · Agent"
    local prompt_desc = ""
    if #node_ids > 0 then
      prompt_desc = "Nodes: " .. table.concat(node_ids, ", ")
    elseif buf_path ~= "" then
      prompt_desc = "No node mapped for current file"
    else
      prompt_desc = "No file open"
    end

    ui.input(prompt_title, {
      placeholder = "What do you want the agent to do? (e.g., 'fix useEffect loop')",
      default = "",
      on_submit = function(text)
        log.info("SadeAgent command invoked", { prompt = text, sade_root = M.state.sade_root })
        agent.invoke(M.state.sade_root, M.state.index, { prompt = text })
      end,
    })
  end, { desc = "Invoke agent with current file's context", nargs = "?" })

  vim.api.nvim_create_user_command("SadeAgentSetup", function()
    log.set_area("init")
    log.info("SadeAgentSetup command invoked")
    agent.setup_interactive()
  end, { desc = "Select which agent CLI to use" })

  vim.api.nvim_create_user_command("SadeStop", function()
    log.set_area("init")
    log.info("SadeStop command invoked")
    agent.stop_all()
  end, { desc = "Stop all running agent requests" })

  vim.api.nvim_create_user_command("SadeHeartbeatStop", function()
    heartbeat.stop()
    node_watcher.stop()
  end, { desc = "Stop SADE heartbeat file watcher" })

  vim.api.nvim_create_user_command("SadeHeartbeatClear", function()
    heartbeat.clear_stale()
  end, { desc = "Clear stale heartbeat indicators" })

  vim.api.nvim_create_user_command("SadeHelp", function()
    M.help()
  end, { desc = "Show SADE command reference" })

  vim.api.nvim_create_user_command("Sade", function()
    local node_actions = require("sade.node_actions")
    node_actions.show_actions()
  end, { desc = "Show node actions: improve, compact, unmap (use telescope if available)" })

  vim.api.nvim_create_user_command("SadeGuide", function()
    M.guide()
  end, { desc = "Show SADE philosophy and workflow guide" })

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
  if config.values.shortcuts.agent then
    vim.keymap.set("n", config.values.shortcuts.agent, function()
      if not M.state then
        vim.notify("[sade] not initialized. Run :SadeInit", vim.log.levels.WARN)
        return
      end

      -- Get current file info for context
      local buf_path = vim.api.nvim_buf_get_name(0)
      local idx = M.state.index
      local node_ids = {}
      if buf_path ~= "" then
        node_ids = index.query(idx, buf_path)
      end

      -- Show input dialog for prompt
      local prompt_title = "SADE · Agent"
      local prompt_desc = ""
      if #node_ids > 0 then
        prompt_desc = "Nodes: " .. table.concat(node_ids, ", ")
      elseif buf_path ~= "" then
        prompt_desc = "No node mapped for current file"
      else
        prompt_desc = "No file open"
      end

      sade_ui.input(prompt_title, {
        placeholder = "What do you want the agent to do?",
        default = "",
        on_submit = function(text)
          log.info("SadeAgent keymap invoked", { prompt = text, sade_root = M.state.sade_root })
          agent.invoke(M.state.sade_root, M.state.index, { prompt = text })
        end,
      })
    end, { desc = "SADE: Invoke agent with context" })
  end

  -- Also map for uppercase variant (if different from agent)
  if config.values.shortcuts.agent_cmd and config.values.shortcuts.agent_cmd ~= config.values.shortcuts.agent then
    vim.keymap.set("n", config.values.shortcuts.agent_cmd, function()
      vim.cmd("SadeAgent")
    end, { desc = "SADE: Invoke agent (command)" })
  end
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

  -- Auto-open Super Tree if configured
  if config.values.tree.auto_open then
    vim.defer_fn(function()
      supertree_ui.toggle(M.state.index)
    end, 100)
  end
end

--- Print current state and, if a buffer is open, its node(s).
function M.info()
  if not M.state then
    vim.notify("[sade] not initialized. Run :SadeInit", vim.log.levels.WARN)
    return
  end

  local active = heartbeat.active_files()
  local lines = {
    "sade root: " .. M.state.sade_root,
    "project root: " .. M.state.project_root,
    "nodes: " .. vim.tbl_count(M.state.index.nodes),
    "indexed files: " .. vim.tbl_count(M.state.index.file_to_nodes),
    "active files: " .. #active,
  }

  local buf_path = vim.api.nvim_buf_get_name(0)
  if buf_path ~= "" then
    local node_ids = index.query(M.state.index, buf_path)
    if #node_ids > 0 then
      table.insert(lines, "current file nodes: " .. table.concat(node_ids, ", "))
    else
      table.insert(lines, "current file: not mapped to any node")
    end

    if heartbeat.is_active(buf_path) then
      table.insert(lines, "current file: ACTIVE (being modified externally)")
    end
  end

  vim.notify(table.concat(lines, "\n"))
end

--- Show command reference popup.
function M.help()
  local lines = {
    "",
    "  ╭─────────────────────────────────────────────────────────╮",
    "  │                     COMMANDS                            │",
    "  ╰─────────────────────────────────────────────────────────╯",
    "",
    "  :SadeInit              Initialize plugin, parse nodes, start heartbeat",
    "  :SadeInfo              Show status: root, nodes, indexed files, current node",
    "",
    "  ╭─────────────────────────────────────────────────────────╮",
    "  │                    SUPER TREE                           │",
    "  ╰─────────────────────────────────────────────────────────╯",
    "",
    "  :SadeTree              Toggle the Super Tree sidebar",
    "",
    "    Tree keymaps:",
    "    Enter / o            Expand/collapse node, or open file",
    "    a                    Invoke agent on node or file",
    "    K                    Edit node markdown file",
    "    R                    Refresh tree",
    "    q                    Close tree",
    "",
    "  ╭─────────────────────────────────────────────────────────╮",
    "  │                  CONTEXT & AGENTS                       │",
    "  ╰─────────────────────────────────────────────────────────╯",
    "",
    "  :SadeContext           Copy current file's context to clipboard",
    "  :SadeSeed              Generate seed prompt for initial nodes",
    "  :SadeAgent / <leader>a  Invoke agent with context (opens input dialog)",
    "                        Shortcut configurable via config.shortcuts.agent",
    "  :SadeAgentSetup        Pick which agent CLI to use",
    "",
    "  ╭─────────────────────────────────────────────────────────╮",
    "  │                      UPKEEP                             │",
    "  ╰─────────────────────────────────────────────────────────╯",
    "",
    "  :SadeUpkeep            Check architecture health",
    "    r                    Run agent (or copy to clipboard if no agent)",
    "    R                    Rebuild index after manual edits",
    "",
    "  ╭─────────────────────────────────────────────────────────╮",
    "  │                    HEARTBEAT                            │",
    "  ╰─────────────────────────────────────────────────────────╯",
    "",
    "  :SadeHeartbeatStop     Stop file watcher",
    "  :SadeHeartbeatClear    Clear stale change indicators",
    "",
    "    Indicators:",
    "    ⠋ ⠙ ⠹ ...           File actively being modified (orange, 60s)",
    "    ●                    File was changed, now settled (dim blue)",
    "",
    "  ╭─────────────────────────────────────────────────────────╮",
    "  │                      HELP                              │",
    "  ╰─────────────────────────────────────────────────────────╯",
    "",
    "  :SadeHelp              This window",
    "  :SadeGuide             Philosophy and workflow guide",
    "",
    "  Press q or Esc to close",
    "",
  }
  sade_ui.popup(lines, { title = "SADE · Help" })
end

--- Show philosophy and workflow guide popup.
function M.guide()
  local lines = {
    "",
    "  ╭─────────────────────────────────────────────────────────────╮",
    "  │                        S A D E                              │",
    "  │           Software Architecture Description Engine          │",
    "  ╰─────────────────────────────────────────────────────────────╯",
    "",
    "  The problem:",
    "",
    "    Coding agents are fast. They modify dozens of files across",
    "    your codebase in seconds. You — the human architect — need",
    "    to keep up. But you can't read every diff in real time.",
    "",
    "  The insight:",
    "",
    "    You don't need to see every line. You need to see which",
    "    parts of your architecture are being touched, and trust",
    "    that agents have the right context to make good decisions.",
    "",
    "  How SADE works:",
    "",
    "    1. You describe your architecture in .sade/nodes/*.md",
    "       Each node is a responsibility — not a folder, but a",
    "       concern: \"auth\", \"database\", \"api-routes\".",
    "",
    "    2. Heartbeat watches for changes. When an agent writes",
    "       to files, you see which architectural nodes are active.",
    "       Orange spinner = happening now. Blue dot = changed.",
    "",
    "    3. Super Tree shows your architecture, not your filesystem.",
    "       Expand nodes to see their files. Spot unmapped files",
    "       that need a home.",
    "",
    "    4. Context injection feeds the right .sade/ contracts to",
    "       agents before they start. They know the rules for the",
    "       part of the system they're touching.",
    "",
    "  The workflow:",
    "",
    "    ┌──────────┐     ┌──────────┐     ┌──────────┐",
    "    │  You     │────▶│  Agent   │────▶│  You     │",
    "    │  scope   │     │  works   │     │  review  │",
    "    │  intent  │     │  with    │     │  via     │",
    "    │  + node  │     │  context │     │  tree    │",
    "    └──────────┘     └──────────┘     └──────────┘",
    "",
    "  Getting started:",
    "",
    "    1. Create .sade/ in your project root",
    "    2. Add README.md (what the project is)",
    "    3. Add SKILL.md (coding patterns, constraints)",
    "    4. Run :SadeSeed to generate initial nodes",
    "    5. Review and adjust the generated nodes/*.md",
    "    6. Run :SadeAgentSetup to pick your agent CLI",
    "    7. Use :SadeAgent or <leader>a for context-aware agent",
    "",
    "    • Nodes are responsibilities, not folders",
    "    • .sade/ is human-maintained, agent-consumed",
    "",
    "  Press q or Esc to close",
    "",
  }
  sade_ui.popup(lines, { title = "SADE · Guide" })
end

return M
