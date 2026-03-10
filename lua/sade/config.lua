local M = {}

M.defaults = {
  -- auto-initialize on VimEnter if .sade/ found
  auto_init = true,

  agent = {
    -- agent CLI: "pi", "claude", or nil (prompts setup on first use)
    cli = nil,
  },

  tree = {
    -- default width of the Super Tree split
    width = 35,
    -- side: "left" or "right"
    side = "left",
  },

  heartbeat = {
    -- ms to wait after last fs event before reloading buffer
    debounce_ms = 100,
    -- ms after last change before transitioning to stale (dim indicator)
    settle_ms = 60000,
    -- ms between spinner frame updates
    spinner_ms = 80,
  },
}

M.values = vim.deepcopy(M.defaults)

---@param opts? table  user overrides
function M.setup(opts)
  M.values = vim.tbl_deep_extend("force", vim.deepcopy(M.defaults), opts or {})
end

return M
