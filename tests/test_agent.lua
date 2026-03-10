require("sade.config").setup()
local agent = require("sade.agent")

local function test_detect()
  local available = agent.detect()
  assert(type(available) == "table", "detect should return a table")
  -- at least one agent should be available in this environment
  assert(#available > 0, "expected at least one agent CLI")
  for _, a in ipairs(available) do
    assert(a.id, "agent should have id")
    assert(a.name, "agent should have name")
    assert(a.version, "agent should have version")
  end
  print("  PASS test_detect")
end

local function test_set_and_get()
  agent.set("pi")
  assert(agent.get_configured() == "pi", "should be set to pi")
  agent.set("claude")
  assert(agent.get_configured() == "claude", "should be set to claude")
  -- reset
  require("sade.config").values.agent.cli = nil
  print("  PASS test_set_and_get")
end

local function test_providers_loaded()
  assert(agent.providers.pi, "pi provider should be loaded")
  assert(agent.providers.claude, "claude provider should be loaded")
  assert(agent.providers.codex, "codex provider should be loaded")
  assert(agent.providers.opencode, "opencode provider should be loaded")
  assert(agent.providers.ollama, "ollama provider should be loaded")
  assert(agent.providers.gemini, "gemini provider should be loaded")
  assert(agent.providers.pi.cmd == "pi", "pi cmd should be 'pi'")
  assert(agent.providers.claude.cmd == "claude", "claude cmd should be 'claude'")
  assert(agent.providers.ollama.cmd == "ollama", "ollama cmd should be 'ollama'")
  print("  PASS test_providers_loaded")
end

local function test_provider_build_cmd()
  local ctx_file = "/tmp/test_ctx.md"
  -- pi
  local cmd = agent.providers.pi.build_cmd(ctx_file, "fix the bug")
  assert(cmd:find("pi"), "pi cmd should contain 'pi'")
  assert(cmd:find("append%-system%-prompt"), "pi should use append-system-prompt")
  -- claude
  cmd = agent.providers.claude.build_cmd(ctx_file, "fix the bug")
  assert(cmd:find("claude"), "claude cmd should contain 'claude'")
  assert(cmd:find("append%-system%-prompt"), "claude should use append-system-prompt")
  -- opencode
  cmd = agent.providers.opencode.build_cmd(ctx_file, "fix the bug")
  assert(cmd:find("opencode run"), "opencode cmd should contain 'opencode run'")
  assert(cmd:find("%-%-file"), "opencode should use --file")
  -- ollama
  cmd = agent.providers.ollama.build_cmd(ctx_file, "fix the bug")
  assert(cmd:find("ollama run"), "ollama cmd should contain 'ollama run'")
  print("  PASS test_provider_build_cmd")
end

print("agent:")
test_detect()
test_set_and_get()
test_providers_loaded()
test_provider_build_cmd()
