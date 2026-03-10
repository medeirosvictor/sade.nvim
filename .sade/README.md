# .sade/ Directory

SADE uses this directory to store architectural context for a project.

## Structure

```
.sade/
├── README.md      # this file
├── SKILL.md       # coding patterns, style, constraints for agents
└── nodes/
    └── {name}.md  # one file per architectural responsibility
```

## Nodes

Each file in `nodes/` describes one architectural responsibility. A node is not a folder — it's a grouping of files that share a concern, regardless of where they live on disk.

### Format

```markdown
# Node Name

Short description of what this node owns and how it works.

## Files
- path/to/file.lua
- path/to/other/**

## Notes
Implementation details, constraints, decisions worth remembering.
```

### Rules

- One node per `.md` file in `nodes/`.
- The `## Files` section lists paths (relative to project root) or globs.
- A file can appear in multiple nodes if it genuinely bridges concerns.
- Nodes are the unit of context: when an agent works on code in a node, it gets that node's markdown + SKILL.md.

## Seeding

Run `:SadeSeed` to have a coding agent read the codebase and generate initial nodes from README.md and SKILL.md. The agent describes what exists — it does not invent architecture. Review and correct the output.

## Maintenance

Agents are instructed (via SKILL.md) to keep nodes updated as they work. When an agent creates, moves, or deletes files, it updates the relevant `nodes/*.md`. This is a contract, not a suggestion.
