require("sade.config").setup()
local seed = require("sade.seed")

local plugin_root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h:h")
local sade_root = plugin_root .. "/.sade"

local function test_build_prompt()
  local prompt = seed.build_prompt(sade_root, plugin_root)

  assert(prompt, "prompt should not be nil")
  -- should contain the instruction header
  assert(prompt:find("describe the architecture"), "should contain instructions")
  -- should contain the node format example
  assert(prompt:find("## Files"), "should contain format example")
  -- should contain project files
  assert(prompt:find("lua/sade/init.lua"), "should list project files")
  -- should NOT contain .git or node_modules files
  assert(not prompt:find("%.git/"), "should not contain .git files")

  print("  PASS test_build_prompt")
end

local function test_prompt_includes_readme()
  local prompt = seed.build_prompt(sade_root, plugin_root)
  assert(prompt:find("Project Overview"), "should include project README section")
  print("  PASS test_prompt_includes_readme")
end

local function test_prompt_includes_skill()
  local prompt = seed.build_prompt(sade_root, plugin_root)
  assert(prompt:find("Coding Patterns"), "should include SKILL section")
  print("  PASS test_prompt_includes_skill")
end

print("seed:")
test_build_prompt()
test_prompt_includes_readme()
test_prompt_includes_skill()
