# Upkeep

Architecture health check and maintenance. Audits the gap between actual files and node descriptions.

## Files
- lua/sade/upkeep.lua

## Notes
`:SadeUpkeep` checks for: unmapped files (not in any node), empty nodes (glob patterns that match nothing). Shows a popup with results and offers two actions: 'r' generates a refresh prompt for your agent to fix the issues, 'R' rebuilds the index after manual edits. Keeps architecture accurate over time.
