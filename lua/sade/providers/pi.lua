--- pi coding agent provider.
--- Uses -p for non-interactive mode with appended context.
---@type SadeProvider
return {
  id = "pi",
  name = "pi",
  cmd = "pi",
  check = "pi --version",
  build_cmd = function(ctx_file, prompt)
    local parts = { "pi", "-p" }
    -- inject context as appended system prompt
    table.insert(parts, "--append-system-prompt " .. vim.fn.shellescape("@" .. ctx_file))
    if prompt then
      table.insert(parts, vim.fn.shellescape(prompt))
    end
    return table.concat(parts, " ")
  end,
}
