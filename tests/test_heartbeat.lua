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
  heartbeat.start(plugin_root)
  heartbeat.stop_silent()
  local files = heartbeat.active_files()
  assert(#files == 0, "expected no active files after stop")
  print("  PASS test_start_stop")
end

local function test_stop_idempotent()
  -- calling stop twice should not error
  heartbeat.stop_silent()
  heartbeat.stop_silent()
  print("  PASS test_stop_idempotent")
end

local function test_sign_definitions()
  require("sade.config").setup()
  local plugin_root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h:h")
  heartbeat.start(plugin_root)

  -- verify spinner signs are defined
  local signs = vim.fn.sign_getdefined("SadeSpinner1")
  assert(#signs > 0, "SadeSpinner1 sign not defined")

  local stale = vim.fn.sign_getdefined("SadeStale")
  assert(#stale > 0, "SadeStale sign not defined")

  heartbeat.stop_silent()
  print("  PASS test_sign_definitions")
end

print("heartbeat:")
test_active_files_empty()
test_is_active_false()
test_start_stop()
test_stop_idempotent()
test_sign_definitions()
