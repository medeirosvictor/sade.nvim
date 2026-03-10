require("sade.config").setup()
local parser = require("sade.parser")
local index = require("sade.index")
local context = require("sade.context")

local plugin_root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h:h")
local sade_root = plugin_root .. "/.sade"
local nodes = parser.parse_all(sade_root .. "/nodes")
local idx = index.build(nodes, plugin_root)

local function test_assemble_mapped_file()
  local filepath = plugin_root .. "/lua/sade/project.lua"
  local ctx, node_ids = context.assemble(sade_root, idx, filepath)

  assert(ctx, "context should not be nil")
  assert(#node_ids > 0, "should have at least one node")
  assert(node_ids[1] == "project", "expected 'project' node, got '" .. node_ids[1] .. "'")

  -- should contain project overview section
  assert(ctx:find("Project Overview"), "should contain project overview")
  -- should contain coding patterns
  assert(ctx:find("Coding Patterns"), "should contain coding patterns")
  -- should contain the node contract
  assert(ctx:find("Node: project"), "should contain the node contract")
  -- should contain current file reference
  assert(ctx:find("lua/sade/project.lua"), "should contain current file path")

  print("  PASS test_assemble_mapped_file")
end

local function test_assemble_unmapped_file()
  local filepath = plugin_root .. "/README.md"
  local ctx, node_ids = context.assemble(sade_root, idx, filepath)

  assert(ctx, "context should not be nil")
  assert(#node_ids == 0, "README.md should not be mapped to a node")
  assert(ctx:find("not mapped to any architectural node"), "should note unmapped status")

  print("  PASS test_assemble_unmapped_file")
end

local function test_assemble_multi_node()
  -- plugin/sade.lua belongs to plugin-core
  local filepath = plugin_root .. "/plugin/sade.lua"
  local ctx, node_ids = context.assemble(sade_root, idx, filepath)

  assert(ctx, "context should not be nil")
  assert(#node_ids > 0, "should have nodes")
  assert(ctx:find("Node:"), "should have at least one node section")

  print("  PASS test_assemble_multi_node")
end

print("context:")
test_assemble_mapped_file()
test_assemble_unmapped_file()
test_assemble_multi_node()
