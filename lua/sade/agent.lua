local M = {}

local config = require("sade.config")
local project = require("sade.project")
local context = require("sade.context")
local ui = require("sade.ui")
local log = require("sade.log")
local throbber = require("sade.throbber")
local tracking = require("sade.tracking")

--- Provider registry — loaded lazily from lua/sade/providers/*.lua
---@type table<string, SadeProvider>
M.providers = {}

--- Tracking for all agent requests
---@type SadeTracking
M.tracking = tracking.Tracking.new()

--- Current throbber instance
---@type SadeThrobber|nil
M._throbber = nil

--- Load order for display consistency.
local PROVIDER_IDS = { "pi", "claude", "codex", "opencode", "gemini", "ollama" }

--- Load all built-in providers.
local function ensure_providers()
  if next(M.providers) then
    return
  end
  for _, id in ipairs(PROVIDER_IDS) do
    local ok, provider = pcall(require, "sade.providers." .. id)
    if ok then
      M.providers[id] = provider
    end
  end
end

--- Detect which agent CLIs are available on the system.
---@return { id: string, name: string, version: string }[]
function M.detect()
  ensure_providers()
  local available = {}
  for _, id in ipairs(PROVIDER_IDS) do
    local provider = M.providers[id]
    if provider then
      local handle = io.popen(provider.check .. " 2>/dev/null")
      if handle then
        local output = handle:read("*a")
        handle:close()
        if output and vim.trim(output) ~= "" then
          table.insert(available, {
            id = id,
            name = provider.name,
            version = vim.trim(output),
          })
        end
      end
    end
  end
  return available
end

--- Get the configured provider id, or nil.
--- Checks project config first, then falls back to global config.
---@return string|nil
function M.get_configured()
  -- check for project-level config first
  local sade = package.loaded["sade"]
  if sade and sade.state and sade.state.sade_root then
    local project_agent = project.load_agent_config(sade.state.sade_root)
    if project_agent and M.providers[project_agent] then
      return project_agent
    end
  end
  -- fall back to global config
  return config.values.agent and config.values.agent.cli or nil
end

--- Get the configured provider, or nil.
---@return SadeProvider|nil
function M.get_provider()
  ensure_providers()
  local id = M.get_configured()
  return id and M.providers[id] or nil
end

--- Set the agent CLI.
---@param provider_id string
function M.set(provider_id)
  ensure_providers()
  if not M.providers[provider_id] then
    log.set_area("agent")
    log.error("Unknown provider", { provider_id = provider_id })
    vim.notify("[sade] unknown provider: " .. provider_id, vim.log.levels.ERROR)
    return
  end

  -- save to global config
  if not config.values.agent then
    config.values.agent = {}
  end
  config.values.agent.cli = provider_id

  -- also save to project config if initialized
  local sade = package.loaded["sade"]
  if sade and sade.state and sade.state.sade_root then
    project.save_agent_config(sade.state.sade_root, provider_id)
    vim.notify(("[sade] agent set to %s (saved to project)"):format(M.providers[provider_id].name))
  else
    vim.notify(("[sade] agent set to %s"):format(M.providers[provider_id].name))
  end
end

--- Interactive setup: detect available agents, let user pick one.
function M.setup_interactive()
  log.set_area("agent")
  log.info("Setting up agent interactively")

  local available = M.detect()

  if #available == 0 then
    log.warn("No agent CLIs found", { checked = PROVIDER_IDS })
    vim.notify("[sade] no agent CLIs found (checked: " .. table.concat(PROVIDER_IDS, ", ") .. ")", vim.log.levels.WARN)
    return
  end

  local items = {}
  for _, a in ipairs(available) do
    table.insert(items, {
      label = ("%s  ·  v%s"):format(a.name, a.version),
      value = a.id,
    })
  end

  ui.select("SADE · Select Agent", items, function(item)
    M.set(item.value)
  end)
end

--- Write context to a temp file.
---@param ctx string
---@return string filepath
local function write_context_file(ctx)
  local tmpfile = vim.fn.tempname() .. ".md"
  local f = io.open(tmpfile, "w")
  if f then
    f:write(ctx)
    f:close()
  end
  return tmpfile
end

--- Write prompt to the sade prompts directory for tracking.
---@param sade_root string
---@param ctx string
---@return string filepath
local function write_prompt_file(sade_root, ctx)
  local prompts_dir = sade_root .. "/tmp/prompts"
  -- ensure directory exists
  vim.fn.mkdir(prompts_dir, "p")
  local prompt_file = prompts_dir .. "/last_prompt.md"
  local f = io.open(prompt_file, "w")
  if f then
    f:write(ctx)
    f:close()
  end
  return prompt_file
end

--- Get or create the agent log file for the current session.
---@param sade_root string
---@return string log_path
local function get_agent_log_path(sade_root)
  local log_dir = sade_root .. "/tmp/logs"
  vim.fn.mkdir(log_dir, "p")
  return log_dir .. "/agent.log"
end

--- Start the throbber (spinner)
local function start_throbber()
  if M._throbber then
    M._throbber:stop()
  end
  M._throbber = throbber.Throbber.new(function(icon)
    -- Update sade.state.agent_running for supertree UI
    local active = M.tracking:active_count()
    if active > 0 then
      local sade = package.loaded["sade"]
      if sade and sade.state then
        sade.state.agent_running = icon
      end
      -- Also refresh supertree if open
      local supertree = package.loaded["sade.supertree_ui"]
      if supertree and supertree.refresh then
        supertree.refresh()
      end
    end
  end, 80)
  M._throbber:start()
end

--- Stop the throbber
local function stop_throbber()
  if M._throbber then
    M._throbber:stop()
    M._throbber = nil
  end
  -- Clear agent_running state
  local sade = package.loaded["sade"]
  if sade and sade.state then
    sade.state.agent_running = nil
  end
  -- Refresh supertree to hide spinner
  local supertree = package.loaded["sade.supertree_ui"]
  if supertree and supertree.refresh then
    supertree.refresh()
  end
end

--- Invoke the agent with context for the given file or node.
---@param sade_root string
---@param idx SadeIndex
---@param opts? { filepath?: string, node_id?: string, prompt?: string }
function M.invoke(sade_root, idx, opts)
  opts = opts or {}
  log.set_area("agent")

  -- derive project_root from sade_root (sade_root is .sade/ directory)
  local project_root = vim.fn.fnamemodify(sade_root, ":h")

  log.debug("agent.invoke called", {
    sade_root = sade_root,
    project_root = project_root,
    has_idx = idx ~= nil,
    opts = opts,
  })

  local provider = M.get_provider()
  if not provider then
    log.warn("No agent configured, prompting setup")
    vim.notify("[sade] no agent configured. Run :SadeAgentSetup", vim.log.levels.WARN)
    M.setup_interactive()
    return
  end

  log.info("Using provider", { provider = provider.name })

  -- assemble context
  local ctx, node_ids
  if opts.prompt then
    -- seed mode: use provided prompt directly, no context assembly needed
    ctx = opts.prompt
    node_ids = {}
  elseif opts.node_id then
    local node = idx.nodes[opts.node_id]
    if not node then
      log.error("Unknown node", { node_id = opts.node_id })
      vim.notify("[sade] unknown node: " .. opts.node_id, vim.log.levels.ERROR)
      return
    end
    local first_file = nil
    for filepath, nids in pairs(idx.file_to_nodes) do
      for _, nid in ipairs(nids) do
        if nid == opts.node_id then
          first_file = filepath
          break
        end
      end
      if first_file then
        break
      end
    end
    if first_file then
      ctx, node_ids = context.assemble(sade_root, idx, first_file)
    else
      ctx = context.assemble(sade_root, idx, sade_root .. "/nodes/" .. opts.node_id .. ".md")
      node_ids = { opts.node_id }
    end
  elseif opts.filepath then
    ctx, node_ids = context.assemble(sade_root, idx, opts.filepath)
  else
    ctx, node_ids = context.assemble_current(sade_root, idx)
    if not ctx then
      -- Fall back to minimal context (README + SKILL) if no file is open
      ctx = context.assemble_minimal(sade_root)
      node_ids = {}
    end
  end

  -- write context to file (use prompt file for seed mode, temp file otherwise)
  local ctx_file
  if opts.prompt then
    -- seed mode: write to persistent prompt file for tracking
    ctx_file = write_prompt_file(sade_root, ctx)
  else
    -- normal mode: write to temp file
    ctx_file = write_context_file(ctx)
  end

  -- build command via provider
  local cmd_str = provider.build_cmd(ctx_file, opts.prompt or "")

  -- prepend cd to project root so agent runs in the right directory
  local full_cmd = { "sh", "-c", "cd " .. vim.fn.shellescape(project_root) .. " && " .. cmd_str }

  log.debug("Agent command built", {
    provider = provider.name,
    cmd = full_cmd,
    nodes = node_ids,
  })

  -- copy full command to clipboard
  local clipboard_cmd = "cd " .. vim.fn.shellescape(project_root) .. " && " .. cmd_str
  vim.fn.setreg("+", clipboard_cmd)

  local nodes_str = #node_ids > 0 and table.concat(node_ids, ", ") or "none"
  log.info("Starting agent", { provider = provider.name, nodes = nodes_str })

  -- Track this request
  local request = M.tracking:track(clipboard_cmd, provider.name)

  -- Start throbber
  start_throbber()

  -- Notify user
  vim.notify(("[sade] Agent %s running (nodes: %s)"):format(provider.name, nodes_str))

  -- Get log path for this session
  local log_path = get_agent_log_path(sade_root)
  -- Open log file for appending
  local log_file = io.open(log_path, "a")
  if log_file then
    log_file:write("\n--- Agent started at " .. os.date("%Y-%m-%d %H:%M:%S") .. " ---\n")
    log_file:write("Nodes: " .. nodes_str .. "\n")
    log_file:write("Context: " .. ctx_file .. "\n\n")
    log_file:close()
  end

  -- Run using vim.system() (modern API)
  local proc = vim.system(full_cmd, {
    text = true,
    stdout = vim.schedule_wrap(function(err, data)
      -- Log to file
      if data and data ~= "" then
        local f = io.open(log_path, "a")
        if f then
          f:write(data)
          f:close()
        end
      end
    end),
    stderr = vim.schedule_wrap(function(err, data)
      -- Log to file
      if data and data ~= "" then
        local f = io.open(log_path, "a")
        if f then
          f:write("[stderr] " .. data)
          f:close()
        end
      end
    end),
  }, vim.schedule_wrap(function(obj)
    -- Append completion message to log
    local f = io.open(log_path, "a")
    if f then
      f:write("\n--- Agent completed with code " .. obj.code .. " ---\n")
      f:close()
    end

    log.info("Agent completed", { code = obj.code, signal = obj.signal })

    -- Stop throbber
    stop_throbber()

    -- Clean up temp file
    os.remove(ctx_file)

    -- Update tracking
    if obj.code == 0 then
      M.tracking:complete(request.id, "success")

      -- Rebuild index and refresh supertree automatically
      local parser = require("sade.parser")
      local idx_mod = require("sade.index")
      local nodes = parser.parse_all(sade_root .. "/nodes")
      local new_idx = idx_mod.build(nodes, project_root)

      -- Update sade state
      local sade = package.loaded["sade"]
      if sade and sade.state then
        sade.state.index = new_idx
      end

      -- Refresh supertree if open
      local supertree = package.loaded["sade.supertree_ui"]
      if supertree and supertree.refresh then
        supertree.refresh()
      end

      vim.notify(("[sade] Agent completed — %d nodes indexed"):format(vim.tbl_count(new_idx.nodes)))
    else
      M.tracking:complete(request.id, "failed")
      vim.notify(("[sade] Agent exited with code %d"):format(obj.code), vim.log.levels.WARN)
    end
  end))

  -- Store proc for cancellation
  request.proc = proc
end

--- Stop all running agent requests
function M.stop_all()
  log.set_area("agent")
  log.info("Stopping all agent requests")

  M.tracking:stop_all()
  stop_throbber()

  local count = M.tracking:active_count()
  if count > 0 then
    vim.notify(("[sade] Stopped %d agent request(s)"):format(count))
  else
    vim.notify("[sade] No running agents to stop")
  end
end

return M
