# Heartbeat

Watch for external file changes (from coding agents) and auto-reload Neovim buffers. Shows sign column indicators on files being actively modified.

## Files
- lua/sade/heartbeat.lua

## Notes
Uses `vim.uv` (libuv) fs_event for recursive directory watching. Debounces rapid changes before reloading. Places signs on line 1 of active buffers. Skips `.git/` and `.sade/` directories. Does not reload buffers with unsaved changes.
