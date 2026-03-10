require("sade.config").setup()
local parser = require("sade.parser")
local index = require("sade.index")
local upkeep = require("sade.upkeep")

local plugin_root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h:h")
local sade_root = plugin_root .. "/.sade"
local nodes = parser.parse_all(sade_root .. "/nodes")
local idx = index.build(nodes, plugin_root)

local function test_check()
  local results = upkeep.check(sade_root, plugin_root, idx)

  assert(results.node_count > 0, "should have nodes")
  assert(results.file_count > 0, "should have indexed files")
  assert(results.unmapped, "should have unmapped array")
  assert(results.empty_nodes, "should have empty_nodes array")

  print("  PASS test_check")
end

local function test_build_refresh_prompt()
  local prompt = upkeep.build_refresh_prompt(sade_root, plugin_root, idx)

  assert(prompt:find("architectural node files"), "should mention node files")
  assert(prompt:find("Nodes:"), "should mention nodes count")
  assert(prompt:find("Indexed files:"), "should mention indexed files")

  print("  PASS test_build_refresh_prompt")
end

print("upkeep:")
test_check()
test_build_refresh_prompt()
