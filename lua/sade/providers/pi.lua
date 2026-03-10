--- pi coding agent provider.
--- Uses --append-system-prompt to inject context from a file.
---@type SadeProvider
return {
  id = "pi",
  name = "pi",
  cmd = "pi",
  check = "pi --version",
  build_cmd = function(ctx_file, prompt)
    local parts = { "pi" }
    -- inject context as appended system prompt
    table.insert(parts, "--append-system-prompt " .. vim.fn.shellescape("@" .. ctx_file))
    if prompt then
      table.insert(parts, vim.fn.shellescape(prompt))
    end
    return table.concat(parts, " ")
  end,
}
