--- OpenAI Codex CLI provider.
--- Uses --full-auto with context piped via instructions flag.
---@type SadeProvider
return {
  id = "codex",
  name = "Codex",
  cmd = "codex",
  check = "codex --version",
  build_cmd = function(ctx_file, prompt)
    local parts = { "codex" }
    -- codex uses --instructions for system context
    table.insert(parts, "--instructions " .. vim.fn.shellescape(ctx_file))
    if prompt then
      table.insert(parts, vim.fn.shellescape(prompt))
    end
    return table.concat(parts, " ")
  end,
}
