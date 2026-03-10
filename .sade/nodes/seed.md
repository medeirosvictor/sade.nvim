# Seed

Generate the initial set of `nodes/*.md` by prompting a coding agent to analyze the codebase.

## Files
- lua/sade/seed.lua

## Notes
Builds a prompt that includes: instructions for the node format, project README, SKILL.md, and a full file listing (skipping .git, node_modules, etc.). The prompt is copied to clipboard for the user to paste into their agent. The agent is instructed to describe what exists, not invent architecture.

## Tests
- tests/test_seed.lua
