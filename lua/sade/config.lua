local M = {}

M.defaults = {
  -- auto-initialize on VimEnter if .sade/ found
  auto_init = true,

  -- Keyboard shortcuts (set to false to disable a shortcut)
  shortcuts = {
    -- Invoke agent with context (opens input dialog)
    agent = "<leader>a",
    -- Invoke agent via command (same as :SadeAgent)
    agent_cmd = "<leader>A",
  },

  agent = {
    -- agent CLI: "pi", "claude", "codex", "opencode", "gemini", "ollama", or nil
    cli = nil,
    -- model for ollama provider (default: codellama)
    ollama_model = "codellama",
  },

  tree = {
    -- auto-open Super Tree on startup (requires auto_init = true)
    auto_open = false,
    -- default width of the Super Tree split
    width = 26,
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
