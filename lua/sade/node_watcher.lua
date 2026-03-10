local M = {}

local log = require("sade.log")

---@class NodeWatcherState
local state = {
  watcher = nil,       -- uv_fs_event_t
  timer = nil,         -- debounce timer
  sade_root = nil,     -- .sade directory path
  project_root = nil,  -- project root (parent of .sade/)
}

--- Rebuild the index and refresh the supertree.
local function rebuild_and_refresh()
  local sade = package.loaded["sade"]
  if not sade or not sade.state or not sade.state.sade_root then
    log.debug("node_watcher: sade not initialized, skipping rebuild")
    return
  end

  local parser = require("sade.parser")
  local index = require("sade.index")

  local nodes_dir = sade.state.sade_root .. "/nodes"
  local nodes = parser.parse_all(nodes_dir)
  local new_idx = index.build(nodes, sade.state.project_root)

  sade.state.index = new_idx

  log.info("node_watcher: index rebuilt", {
    node_count = vim.tbl_count(new_idx.nodes),
    file_count = vim.tbl_count(new_idx.file_to_nodes),
  })

  -- notify user
  vim.notify(("[sade] nodes updated — %d nodes, %d files"):format(
    vim.tbl_count(new_idx.nodes),
    vim.tbl_count(new_idx.file_to_nodes)
  ))

  -- refresh super tree if open
  local supertree = require("sade.supertree_ui")
  if supertree and supertree.refresh then
    supertree.refresh()
  end
end

--- Handle a change event from the watcher.
---@param err string|nil
---@param filename string|nil
---@param events table
local function on_changed(err, filename, events)
  if err then
    log.warn("node_watcher: error", { error = err })
    return
  end

  if not filename then
    return
  end

  -- only care about .md files in nodes/
  if not filename:match("%.md$") then
    return
  end
  if not filename:match("^nodes/") and not filename:match("/nodes/") then
    return
  end

  log.debug("node_watcher: change detected", { filename = filename, events = events })

  -- debounce: don't rebuild on every single write
  if state.timer then
    state.timer:stop()
    state.timer:close()
  end

  state.timer = vim.uv.new_timer()
  state.timer:start(300, 0, function()
    state.timer:stop()
    state.timer:close()
    state.timer = nil

    vim.schedule(rebuild_and_refresh)
  end)
end

--- Start watching the .sade/nodes directory for changes.
---@param sade_root string  absolute path to .sade/
---@param project_root string  absolute path to project root
function M.start(sade_root, project_root)
  if state.watcher then
    log.debug("node_watcher: already running")
    return
  end

  state.sade_root = sade_root
  state.project_root = project_root

  local nodes_dir = sade_root .. "/nodes"

  -- check if nodes directory exists
  local stat = vim.uv.fs_stat(nodes_dir)
  if not stat then
    log.debug("node_watcher: nodes directory does not exist", { nodes_dir = nodes_dir })
    return
  end

  state.watcher = vim.uv.new_fs_event()
  if not state.watcher then
    log.warn("node_watcher: failed to create fs event")
    return
  end

  local ok, err = pcall(function()
    state.watcher:start(nodes_dir, { recursive = true }, on_changed)
  end)

  if not ok then
    log.warn("node_watcher: failed to start", { error = err })
    state.watcher:close()
    state.watcher = nil
    return
  end

  log.info("node_watcher: started", { nodes_dir = nodes_dir })
end

--- Stop watching for node changes.
function M.stop()
  if state.timer then
    state.timer:stop()
    state.timer:close()
    state.timer = nil
  end

  if state.watcher then
    state.watcher:stop()
    state.watcher:close()
    state.watcher = nil
  end

  state.sade_root = nil
  state.project_root = nil

  log.debug("node_watcher: stopped")
end

return M
