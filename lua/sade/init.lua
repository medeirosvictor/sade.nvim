local config = require("sade.config")
local project = require("sade.project")
local parser = require("sade.parser")
local index = require("sade.index")
local heartbeat = require("sade.heartbeat")
local supertree_ui = require("sade.supertree_ui")
local context = require("sade.context")
local seed = require("sade.seed")

local M = {}

--- Plugin state (nil until initialized)
---@type { sade_root: string, project_root: string, index: SadeIndex }|nil
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
    seed.run(M.state.sade_root, M.state.project_root)
  end, { desc = "Generate seed prompt for creating initial nodes" })

  vim.api.nvim_create_user_command("SadeHeartbeatStop", function()
    heartbeat.stop()
  end, { desc = "Stop SADE heartbeat file watcher" })

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
end

--- Initialize: find .sade/, validate, parse nodes, build index, start heartbeat.
function M.init()
  -- stop existing heartbeat if re-initializing
  heartbeat.stop_silent()

  local sade_root, err = project.find_root()
  if not sade_root then
    vim.notify("[sade] " .. err, vim.log.levels.ERROR)
    return
  end

  local ok, verr = project.validate(sade_root)
  if not ok then
    vim.notify("[sade] " .. verr, vim.log.levels.ERROR)
    return
  end

  local project_root = vim.fn.fnamemodify(sade_root, ":h")
  local nodes = parser.parse_all(sade_root .. "/nodes")
  local idx = index.build(nodes, project_root)

  M.state = {
    sade_root = sade_root,
    project_root = project_root,
    index = idx,
  }

  heartbeat.start(project_root)

  local count = #nodes
  vim.notify(("[sade] initialized — %d node%s loaded, heartbeat on"):format(count, count == 1 and "" or "s"))
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

return M
