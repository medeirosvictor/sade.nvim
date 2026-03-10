local parser = require("sade.parser")

local function test_parse_file()
  -- parse the plugin's own node file
  local plugin_root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h:h")
  local node_path = plugin_root .. "/.sade/nodes/plugin-core.md"

  local node, err = parser.parse_file(node_path)
  assert(node, "parse failed: " .. (err or ""))
  assert(node.id == "plugin-core", "id: expected 'plugin-core', got '" .. node.id .. "'")
  assert(node.label == "Plugin Core", "label: expected 'Plugin Core', got '" .. node.label .. "'")
  assert(#node.files == 3, "files: expected 3, got " .. #node.files)
  assert(node.files[1] == "plugin/sade.lua", "files[1]: got '" .. node.files[1] .. "'")
  assert(node.description ~= "", "description should not be empty")
  assert(node.notes ~= "", "notes should not be empty")
  print("  PASS test_parse_file")
end

local function test_parse_all()
  local plugin_root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h:h")
  local nodes = parser.parse_all(plugin_root .. "/.sade/nodes")
  assert(#nodes >= 4, "expected at least 4 nodes, got " .. #nodes)

  local ids = {}
  for _, n in ipairs(nodes) do
    ids[n.id] = true
  end
  assert(ids["plugin-core"], "missing plugin-core node")
  assert(ids["project"], "missing project node")
  assert(ids["parser"], "missing parser node")
  assert(ids["index"], "missing index node")
  print("  PASS test_parse_all")
end

print("parser:")
test_parse_file()
test_parse_all()
