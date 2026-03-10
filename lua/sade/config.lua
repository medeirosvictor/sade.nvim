local M = {}

M.defaults = {
  -- auto-initialize on VimEnter if .sade/ found
  auto_init = true,

  heartbeat = {
    -- ms to wait after last fs event before reloading buffer
    debounce_ms = 100,
    -- ms after last change before transitioning to settled
    settle_ms = 2000,
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
