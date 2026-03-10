local M = {}

--- Default AGENTS.md template for new projects
M.AGENTS_TEMPLATE = [[
# AGENTS.md

This file contains instructions for coding agents working on this project.

## SADE Integration

This project uses [SADE](https://github.com/medeirosvictor/sade.nvim) for architecture management.

### For Agents

When working on this codebase:

1. **Read context** — Start by reading `.sade/README.md` and `.sade/SKILL.md`
2. **Find relevant nodes** — Look in `.sade/nodes/` for architectural contracts
3. **Maintain nodes** — If you create/move/delete files, update the relevant node markdown
4. **Check health** — Run `:SadeUpkeep` or equivalent to find unmapped files

### Context Injection

When invoking an agent with context, it receives:
- Project README
- SKILL.md (coding patterns)
- Relevant node contracts
- Current file path

]]

return M
