# Plugin Core

Entry point, setup, configuration, and top-level state management for sade.nvim.

## Files
- DEV-PLAN.md
- README.md
- lua/sade/log.lua
- plugin/sade.lua
- lua/sade/init.lua
- lua/sade/config.lua
- tests/minimal_init.lua

## Notes
This is the plugin loader and user-facing setup API. Registers commands (:SadeInit, :SadeInfo, :SadeHeartbeatStop), merges user config with defaults, and starts heartbeat on init.
