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

local function test_agents_defined()
  assert(agent.agents.pi, "pi should be defined")
  assert(agent.agents.claude, "claude should be defined")
  assert(agent.agents.pi.cmd == "pi", "pi cmd should be 'pi'")
  assert(agent.agents.claude.cmd == "claude", "claude cmd should be 'claude'")
  print("  PASS test_agents_defined")
end

print("agent:")
test_detect()
test_set_and_get()
test_agents_defined()
