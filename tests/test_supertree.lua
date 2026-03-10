require("sade.config").setup()
local parser = require("sade.parser")
local index = require("sade.index")
local supertree = require("sade.supertree")

local plugin_root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h:h")
local nodes = parser.parse_all(plugin_root .. "/.sade/nodes")
local idx = index.build(nodes, plugin_root)

local function test_build_entries_collapsed()
  local entries = supertree.build_entries(idx, {})
  -- should have at least one entry per node, all collapsed
  local node_count = 0
  for _, e in ipairs(entries) do
    if e.type == "node" then
      node_count = node_count + 1
      assert(not e.expanded, "nodes should be collapsed by default")
      assert(e.file_count, "nodes should have file_count")
    end
  end
  assert(node_count >= 4, "expected at least 4 nodes, got " .. node_count)
  -- no file entries when collapsed
  for _, e in ipairs(entries) do
    assert(e.type ~= "file", "should not have file entries when collapsed")
  end
  print("  PASS test_build_entries_collapsed")
end

local function test_build_entries_expanded()
  local expanded = { ["plugin-core"] = true }
  local entries = supertree.build_entries(idx, expanded)

  -- find plugin-core node and check it's expanded
  local found_node = false
  local file_entries = 0
  local in_plugin_core = false
  for _, e in ipairs(entries) do
    if e.type == "node" and e.id == "plugin-core" then
      found_node = true
      assert(e.expanded, "plugin-core should be expanded")
      in_plugin_core = true
    elseif e.type == "node" then
      in_plugin_core = false
    elseif e.type == "file" and in_plugin_core then
      file_entries = file_entries + 1
      assert(e.filepath, "file entry should have filepath")
      assert(e.rel_path, "file entry should have rel_path")
      assert(e.depth == 1, "file entries should be depth 1")
    end
  end
  assert(found_node, "should find plugin-core node")
  assert(file_entries > 0, "expanded node should show files, got " .. file_entries)
  print("  PASS test_build_entries_expanded")
end

local function test_entries_sorted()
  local entries = supertree.build_entries(idx, {})
  local prev_label = ""
  for _, e in ipairs(entries) do
    if e.type == "node" then
      assert(e.label >= prev_label, "nodes should be sorted: '" .. prev_label .. "' > '" .. e.label .. "'")
      prev_label = e.label
    end
  end
  print("  PASS test_entries_sorted")
end

local function test_unmapped_section()
  local entries = supertree.build_entries(idx, {})
  local has_unmapped = false
  for _, e in ipairs(entries) do
    if e.type == "unmapped_header" then
      has_unmapped = true
      assert(e.file_count > 0, "unmapped should have files")
    end
  end
  -- we expect unmapped files (README.md, DEV-PLAN.md, tests, etc.)
  assert(has_unmapped, "should have unmapped section")
  print("  PASS test_unmapped_section")
end

print("supertree:")
test_build_entries_collapsed()
test_build_entries_expanded()
test_entries_sorted()
test_unmapped_section()
