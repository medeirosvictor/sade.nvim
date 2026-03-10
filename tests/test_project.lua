local project = require("sade.project")

local function test_find_root()
  local plugin_root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h:h")
  -- start from inside the plugin, should find .sade/
  local root, err = project.find_root(plugin_root .. "/lua/sade")
  assert(root, "find_root failed: " .. (err or ""))
  assert(root == plugin_root .. "/.sade", "expected " .. plugin_root .. "/.sade, got " .. root)
  print("  PASS test_find_root")
end

local function test_find_root_not_found()
  local root, err = project.find_root("/tmp")
  assert(root == nil, "expected nil for /tmp")
  assert(err, "expected error message")
  print("  PASS test_find_root_not_found")
end

local function test_validate()
  local plugin_root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h:h")
  local ok, err = project.validate(plugin_root .. "/.sade")
  assert(ok, "validate failed: " .. (err or ""))
  print("  PASS test_validate")
end

print("project:")
test_find_root()
test_find_root_not_found()
test_validate()
