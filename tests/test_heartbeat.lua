local heartbeat = require("sade.heartbeat")

local function test_active_files_empty()
  local files = heartbeat.active_files()
  assert(#files == 0, "expected no active files initially")
  print("  PASS test_active_files_empty")
end

local function test_is_active_false()
  assert(not heartbeat.is_active("/tmp/fake.lua"), "expected is_active false for unknown file")
  print("  PASS test_is_active_false")
end

local function test_start_stop()
  local plugin_root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h:h")
  -- start should not error
  heartbeat.start(plugin_root)
  -- stop should not error
  heartbeat.stop_silent()
  -- active files should be empty after stop
  local files = heartbeat.active_files()
  assert(#files == 0, "expected no active files after stop")
  print("  PASS test_start_stop")
end

print("heartbeat:")
test_active_files_empty()
test_is_active_false()
test_start_stop()
