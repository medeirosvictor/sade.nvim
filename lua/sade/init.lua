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

  vim.api.nvim_create_user_command("SadePrompt", function()
    if not M.state then
      vim.notify("[sade] not initialized. Run :SadeInit", vim.log.levels.WARN)
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
      local prompt_title = "SADE · Prompt (selection)"
      local prompt_desc = "Query about selected code"
      if #node_ids > 0 then
        prompt_desc = prompt_desc .. " | Nodes: " .. table.concat(node_ids, ", ")
      end

      ui.input(prompt_title, {
        placeholder = "What do you want? (e.g., 'explain this', 'refactor this')",
        default = "",
        on_submit = function(text)
          log.info("SadePrompt visual invoked", { prompt = text, sade_root = M.state.sade_root })
          visual.run_visual(M.state.sade_root, M.state.index, { prompt = text })
        end,
      })
    else
      -- No selection: open prompt buffer
      local prompt = require("sade.prompt")

      -- Get current file info for context
      local buf_path = vim.api.nvim_buf_get_name(0)
      local idx = M.state.index
      local node_ids = {}
      if buf_path ~= "" then
        node_ids = require("sade.index").query(idx, buf_path)
      end

      local default_text = ""
      if #node_ids > 0 then
        default_text = "-- Context: nodes " .. table.concat(node_ids, ", ") .. "\n"
      elseif buf_path ~= "" then
        default_text = "-- Context: " .. buf_path .. " (not mapped to a node)\n"
      else
        default_text = "-- Context: no file open\n"
      end

      prompt.open({
        title = "SADE · Prompt",
        default_text = default_text,
        on_submit = function(text)
          log.info("SadePrompt invoked", { prompt = text, sade_root = M.state.sade_root })
          agent.invoke(M.state.sade_root, M.state.index, { prompt = text })
        end,
        on_cancel = function()
          -- Nothing to do
        end,
      })
    end
  end, { desc = "Prompt agent with selection or open prompt buffer", nargs = "?" })

  vim.api.nvim_create_user_command("SadeSetup", function()
    log.set_area("init")
    log.info("SadeSetup command invoked")

    -- Open a popup to show loading state
    local ui = require("sade.ui")
    local loading_bufnr

    -- Show loading spinner
    local spinner_frames = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }
    local frame = 1
    local timer = vim.uv.new_timer()

    local function update_spinner()
      frame = (frame % #spinner_frames) + 1
      if loading_bufnr and vim.api.nvim_buf_is_valid(loading_bufnr) then
        local lines = {
          "",
          "  " .. spinner_frames[frame] .. " Scanning for coding agents...",
          "",
          "  Detecting available agent CLIs...",
        }
        vim.api.nvim_buf_set_lines(loading_bufnr, 0, -1, false, lines)
      end
    end

    -- Start spinner
    timer:start(0, 80, function()
      vim.schedule(update_spinner)
    end)

    -- Show initial popup
    loading_bufnr = ui.popup({
      "",
      "  ⠋ Scanning for coding agents...",
      "",
      "  Detecting available agent CLIs...",
    }, { title = "SADE · Setup", close = false })

    -- Run the detection
    local available = agent.detect()

    -- Stop spinner
    timer:stop()
    timer:close()

    -- Close loading popup
    if loading_bufnr and vim.api.nvim_buf_is_valid(loading_bufnr) then
      vim.api.nvim_buf_delete(loading_bufnr, { force = true })
    end

    if #available == 0 then
      vim.notify("[sade] No agent CLIs found", vim.log.levels.WARN)
      return
    end

    -- Show selection
    local items = {}
    for _, a in ipairs(available) do
      table.insert(items, {
        label = ("%s  ·  v%s"):format(a.name, a.version),
        value = a.id,
      })
    end

    ui.select("SADE · Select Agent", items, function(item)
      agent.set(item.value)
    end)
  end, { desc = "Scan for agent CLIs and configure" })

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
  end, { desc = "Show SADE command reference and guide" })

  vim.api.nvim_create_user_command("Sade", function()
    local node_actions = require("sade.node_actions")
    node_actions.show_actions()
  end, { desc = "Show node actions: improve, compact, unmap (use telescope if available)" })

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
    end, { desc = "SADE: Prompt agent (opens buffer or uses selection)" })
  end

  -- Also map for uppercase variant (if different from prompt)
  if config.values.shortcuts.prompt_cmd and config.values.shortcuts.prompt_cmd ~= config.values.shortcuts.prompt then
    vim.keymap.set("n", config.values.shortcuts.prompt_cmd, function()
      vim.cmd("SadePrompt")
    end, { desc = "SADE: Prompt agent (command)" })
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

--- Show command reference and philosophy guide.
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
    "  │                  CONTEXT & PROMPT                      │",
    "  ╰─────────────────────────────────────────────────────────╯",
    "",
    "  :SadeContext           Copy current file's context to clipboard",
    "  :SadeSeed              Generate seed prompt for initial nodes",
    "  :SadePrompt            Prompt agent (opens buffer, :w:q to submit)",
    "                        Select text first for targeted queries",
    "  :SadeSetup            Scan for agent CLIs and configure",
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
    "  │                    HEARTBEAT                           │",
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
    "  │                      ABOUT                              │",
    "  ╰─────────────────────────────────────────────────────────╯",
    "",
    "  SADE = Software Architecture Description Engine",
    "",
    "  Describe your architecture in .sade/nodes/*.md",
    "  Each node is a responsibility, not a folder.",
    "",
    "  Heartbeat watches for changes. When an agent writes",
    "  to files, you see which architectural nodes are active.",
    "",
    "  Nodes are human-maintained, agent-consumed.",
    "",
    "  Press q or Esc to close",
    "",
  }
  sade_ui.popup(lines, { title = "SADE · Help" })
end

return M
