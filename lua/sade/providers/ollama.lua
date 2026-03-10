--- Ollama provider.
--- Runs a local model with context prepended to the prompt.
--- Requires a model to be configured (defaults to codellama).
---@type SadeProvider
return {
  id = "ollama",
  name = "Ollama",
  cmd = "ollama",
  check = "ollama --version",
  build_cmd = function(ctx_file, prompt)
    -- read context and prepend to prompt
    local ctx = ""
    local f = io.open(ctx_file, "r")
    if f then
      ctx = f:read("*a")
      f:close()
    end

    local full_prompt = ctx
    if prompt then
      full_prompt = full_prompt .. "\n\n---\n\n" .. prompt
    end

    -- default model — user can override via config
    local model = "codellama"
    local sade_config = package.loaded["sade.config"]
    if sade_config and sade_config.values.agent and sade_config.values.agent.ollama_model then
      model = sade_config.values.agent.ollama_model
    end

    local parts = { "ollama", "run", model }
    table.insert(parts, vim.fn.shellescape(full_prompt))
    return table.concat(parts, " ")
  end,
}
