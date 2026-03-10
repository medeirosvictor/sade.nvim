local parser = require("sade.parser")
local index = require("sade.index")

local function test_build_and_query()
  local plugin_root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h:h")
  local nodes = parser.parse_all(plugin_root .. "/.sade/nodes")
  local idx = index.build(nodes, plugin_root)

  -- plugin-core node should own plugin/sade.lua
  local target = plugin_root .. "/plugin/sade.lua"
  local ids = index.query(idx, target)
  assert(#ids > 0, "expected plugin/sade.lua to be mapped, got 0 nodes")

  local found = false
  for _, id in ipairs(ids) do
    if id == "plugin-core" then
      found = true
    end
  end
  assert(found, "plugin/sade.lua should belong to plugin-core node")
  print("  PASS test_build_and_query")
end

local function test_query_nodes()
  local plugin_root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h:h")
  local nodes = parser.parse_all(plugin_root .. "/.sade/nodes")
  local idx = index.build(nodes, plugin_root)

  local target = plugin_root .. "/lua/sade/project.lua"
  local result = index.query_nodes(idx, target)
  assert(#result > 0, "expected project.lua to have nodes")
  assert(result[1].id == "project", "expected 'project' node, got '" .. result[1].id .. "'")
  print("  PASS test_query_nodes")
end

local function test_unmapped_file()
  local plugin_root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h:h")
  local nodes = parser.parse_all(plugin_root .. "/.sade/nodes")
  local idx = index.build(nodes, plugin_root)

  local ids = index.query(idx, plugin_root .. "/nonexistent.lua")
  assert(#ids == 0, "unmapped file should return empty list")
  print("  PASS test_unmapped_file")
end

print("index:")
test_build_and_query()
test_query_nodes()
test_unmapped_file()
