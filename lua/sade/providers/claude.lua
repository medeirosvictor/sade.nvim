--- Claude Code provider.
--- Uses --append-system-prompt to inject context from a file.
---@type SadeProvider
return {
  id = "claude",
  name = "Claude Code",
  cmd = "claude",
  check = "claude --version",
  build_cmd = function(ctx_file, prompt)
    local parts = { "claude" }
    -- inject context as appended system prompt
    table.insert(parts, "--append-system-prompt " .. vim.fn.shellescape("@" .. ctx_file))
    if prompt then
      table.insert(parts, vim.fn.shellescape(prompt))
    end
    return table.concat(parts, " ")
  end,
}
