--- OpenCode provider.
--- Uses `opencode run` with context injected via --file flag and message as args.
---@type SadeProvider
return {
  id = "opencode",
  name = "OpenCode",
  cmd = "opencode",
  check = "opencode --version",
  build_cmd = function(ctx_file, prompt)
    local parts = { "opencode", "run" }
    -- attach context file
    table.insert(parts, "--file " .. vim.fn.shellescape(ctx_file))
    if prompt then
      table.insert(parts, vim.fn.shellescape(prompt))
    else
      table.insert(parts, vim.fn.shellescape("Use the attached context file for architectural guidance."))
    end
    return table.concat(parts, " ")
  end,
}
