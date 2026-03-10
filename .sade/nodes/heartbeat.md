# Heartbeat

Watch for external file changes (from coding agents) and auto-reload Neovim buffers. Animated spinner on active files, settled transition, bulk change notifications.

## Files
- lua/sade/heartbeat.lua

## Notes
Uses `vim.uv` (libuv) fs_event for recursive directory watching. Debounces rapid changes before reloading. Spinner animation (braille frames at 80ms) cycles on sign column line 1 of all active buffers. When a file settles (no changes for 2s), transitions to `○` briefly then clears. Bulk notification fires after a burst settles ("N files updated"). Skips `.git/` and `.sade/` directories. Does not reload buffers with unsaved changes.
