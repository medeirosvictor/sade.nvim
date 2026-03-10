# Plugin Core

Entry point, setup, configuration, and top-level state management for sade.nvim.

## Files
- plugin/sade.lua
- lua/sade/init.lua
- lua/sade/config.lua

## Notes
This is the plugin loader and user-facing setup API. Registers commands (:SadeInit, :SadeInfo, :SadeHeartbeatStop), merges user config with defaults, and starts heartbeat on init.
