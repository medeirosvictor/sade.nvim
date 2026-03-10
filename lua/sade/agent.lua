local M = {}

local config = require("sade.config")
local project = require("sade.project")
local context = require("sade.context")
local ui = require("sade.ui")
local log = require("sade.log")

--- Provider registry — loaded lazily from lua/sade/providers/*.lua
---@type table<string, SadeProvider>
M.providers = {}

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
  local available = M.detect()

  if #available == 0 then
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

--- Invoke the agent with context for the given file or node.
---@param sade_root string
---@param idx SadeIndex
---@param opts? { filepath?: string, node_id?: string, prompt?: string }
function M.invoke(sade_root, idx, opts)
  opts = opts or {}

  -- derive project_root from sade_root (sade_root is .sade/ directory)
  local project_root = vim.fn.fnamemodify(sade_root, ":h")

  log.info("agent.invoke called", {
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
  if opts.node_id then
    local node = idx.nodes[opts.node_id]
    if not node then
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
      vim.notify("[sade] no file open", vim.log.levels.WARN)
      return
    end
  end

  -- write context to temp file
  local ctx_file = write_context_file(ctx)

  -- build command via provider
  local cmd_str = provider.build_cmd(ctx_file, opts.prompt)

  -- prepend cd to project root so agent runs in the right directory
  cmd_str = "cd " .. vim.fn.shellescape(project_root) .. " && " .. cmd_str

  log.info("Agent command built", {
    provider = provider.name,
    cmd = cmd_str,
    nodes = node_ids,
  })

  -- copy full command to clipboard
  vim.fn.setreg("+", cmd_str)

  local nodes_str = #node_ids > 0 and table.concat(node_ids, ", ") or "none"
  vim.notify(("[sade] invoking %s (nodes: %s)\nContext also copied to clipboard"):format(provider.name, nodes_str))

  -- set agent running flag for UI feedback
  local sade = package.loaded["sade"]
  if sade and sade.state then
    sade.state.agent_running = vim.uv.now()

    -- auto-clear after 5 minutes (assume agent is done)
    vim.defer_fn(function()
      if sade and sade.state and sade.state.agent_running then
        sade.state.agent_running = nil
      end
    end, 300000)
  end

  -- use toggleterm if available, otherwise plain terminal
  local ok, toggleterm = pcall(require, "toggleterm.terminal")
  if ok then
    local Terminal = toggleterm.Terminal
    local term = Terminal:new({
      cmd = cmd_str,
      direction = "float",
      float_opts = { border = "curved", width = math.floor(vim.o.columns * 0.85), height = math.floor(vim.o.lines * 0.85) },
      close_on_exit = false,
      on_exit = function()
        os.remove(ctx_file)
        -- clear agent running flag
        if sade and sade.state then
          sade.state.agent_running = nil
        end
      end,
    })
    term:toggle()
  else
    vim.cmd("botright split | terminal " .. cmd_str)
  end
end

return M
