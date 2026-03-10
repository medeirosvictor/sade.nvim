# Context

Assemble scoped architectural context for a file. Reads node contracts, SKILL.md, and README.md into a single markdown string for feeding to coding agents.

## Files
- lua/sade/context.lua

## Notes
Given a file path, finds its node(s) via the index, reads each node's markdown, prepends project README and SKILL, appends the current file path. For unmapped files, includes a note that the file has no node. Output is a single markdown string suitable for clipboard or agent input.
