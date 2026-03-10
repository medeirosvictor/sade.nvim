# Statusline

Lualine component showing current node name with heartbeat state indicators.

## Files
- lua/sade/statusline.lua

## Notes
Shows the node name(s) for the current buffer in the statusline. Colors shift based on heartbeat state: orange/yellow spinner when files in the node are actively being modified by an agent, dim blue with `●` when stale (changed but settled), subtle gray when clean. Refreshes the statusline at 80ms during active state for smooth spinner animation.
