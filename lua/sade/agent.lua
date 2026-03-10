local M = {}

local config = require("sade.config")
local context = require("sade.context")

---@class AgentDef
---@field name string         display name
---@field cmd string          CLI command
---@field check string        version check command
---@field build_args fun(ctx_file: string, prompt: string|nil): string[]  build CLI args

--- Known agent definitions.
---@type table<string, AgentDef>
M.agents = {
  pi = {
    name = "pi",
    cmd = "pi",
    check = "pi --version",
    build_args = function(ctx_file, prompt)
      local args = {}
      if prompt then
        table.insert(args, prompt)
      end
      return args
    end,
  },
  claude = {
    name = "Claude Code",
    cmd = "claude",
    check = "claude --version",
    build_args = function(ctx_file, prompt)
      local args = {}
      if prompt then
        table.insert(args, prompt)
      end
      return args
    end,
  },
}

--- Detect which agent CLIs are available on the system.
---@return { name: string, version: string }[]
function M.detect()
  local available = {}
  for id, def in pairs(M.agents) do
    local handle = io.popen(def.check .. " 2>/dev/null")
    if handle then
      local output = handle:read("*a")
      handle:close()
      if output and output ~= "" then
        table.insert(available, {
          id = id,
          name = def.name,
          version = vim.trim(output),
        })
      end
    end
  end
  table.sort(available, function(a, b)
    return a.name < b.name
  end)
  return available
end

--- Get the configured agent id, or nil.
---@return string|nil
function M.get_configured()
  return config.values.agent and config.values.agent.cli or nil
end

--- Set the agent CLI.
---@param agent_id string
function M.set(agent_id)
  if not M.agents[agent_id] then
    vim.notify("[sade] unknown agent: " .. agent_id, vim.log.levels.ERROR)
    return
  end
  if not config.values.agent then
    config.values.agent = {}
  end
  config.values.agent.cli = agent_id
  vim.notify(("[sade] agent set to %s"):format(M.agents[agent_id].name))
end

--- Interactive setup: detect available agents, let user pick one.
function M.setup_interactive()
  local available = M.detect()

  if #available == 0 then
    vim.notify("[sade] no agent CLIs found (checked: pi, claude)", vim.log.levels.WARN)
    return
  end

  local items = {}
  for _, a in ipairs(available) do
    table.insert(items, ("%s  (%s)"):format(a.name, a.version))
  end

  vim.ui.select(items, {
    prompt = "Select agent CLI:",
  }, function(_, idx)
    if idx then
      M.set(available[idx].id)
    end
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

  local agent_id = M.get_configured()
  if not agent_id then
    vim.notify("[sade] no agent configured. Run :SadeAgentSetup", vim.log.levels.WARN)
    M.setup_interactive()
    return
  end

  local def = M.agents[agent_id]
  if not def then
    vim.notify("[sade] unknown agent: " .. agent_id, vim.log.levels.ERROR)
    return
  end

  -- assemble context
  local ctx, node_ids
  if opts.node_id then
    -- build context for all files in the node
    local node = idx.nodes[opts.node_id]
    if not node then
      vim.notify("[sade] unknown node: " .. opts.node_id, vim.log.levels.ERROR)
      return
    end
    -- find first file in the node to get context (context includes the node contract)
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
      -- node has no resolved files, assemble minimal context
      ctx = context.assemble(sade_root, idx, sade_root .. "/nodes/" .. opts.node_id .. ".md")
      node_ids = { opts.node_id }
    end
  elseif opts.filepath then
    ctx, node_ids = context.assemble(sade_root, idx, opts.filepath)
  else
    -- current buffer
    ctx, node_ids = context.assemble_current(sade_root, idx)
    if not ctx then
      vim.notify("[sade] no file open", vim.log.levels.WARN)
      return
    end
  end

  -- write context to temp file
  local ctx_file = write_context_file(ctx)

  -- build command
  local args = def.build_args(ctx_file, opts.prompt)
  local cmd_parts = { def.cmd }
  for _, arg in ipairs(args) do
    table.insert(cmd_parts, vim.fn.shellescape(arg))
  end
  local cmd_str = table.concat(cmd_parts, " ")

  -- copy context to clipboard as well (fallback)
  vim.fn.setreg("+", ctx)

  local nodes_str = #node_ids > 0 and table.concat(node_ids, ", ") or "none"
  vim.notify(("[sade] invoking %s (nodes: %s)\nContext also copied to clipboard"):format(def.name, nodes_str))

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
        -- clean up temp file
        os.remove(ctx_file)
      end,
    })
    term:toggle()
  else
    vim.cmd("botright split | terminal " .. cmd_str)
  end
end

return M
