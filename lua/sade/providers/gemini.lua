--- Gemini CLI provider.
--- Uses the gemini CLI (google-gemini/gemini-cli) with context as system instruction.
---@type SadeProvider
return {
  id = "gemini",
  name = "Gemini",
  cmd = "gemini",
  check = "gemini --version",
  build_cmd = function(ctx_file, prompt)
    -- read context for system instruction
    local ctx = ""
    local f = io.open(ctx_file, "r")
    if f then
      ctx = f:read("*a")
      f:close()
    end

    local parts = { "gemini" }
    -- use -s for system instruction
    table.insert(parts, "-s " .. vim.fn.shellescape(ctx))
    if prompt then
      table.insert(parts, vim.fn.shellescape(prompt))
    end
    return table.concat(parts, " ")
  end,
}
