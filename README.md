# sade.nvim

Neovim plugin for live file sync during AI-assisted coding and context-aware agent invocation.

## What It Does

1. **Heartbeat** — Detects external file changes (from coding agents) and refreshes buffers. Shows loading indicators on files being modified in real time.

2. **Super Tree** — A semantic file tree organized by architectural responsibility, not filesystem paths. Files are grouped into nodes based on what they do. Heartbeat ripples show which nodes are being touched.

3. **Context Injection** — Maps the current file to its node and feeds scoped context (node contract + SKILL.md) to the coding agent. The agent gets exactly what it needs without reading the whole codebase.

## Requirements

- Neovim ≥ 0.10
- A `.sade/` directory in your project root

## Install

```lua
-- lazy.nvim
{ "medeirosvictor/sade.nvim" }
```

## Data

The plugin reads `.sade/` at your project root:

```
.sade/
├── README.md       # guide for this directory
├── SKILL.md        # coding patterns, constraints, agent rules
└── nodes/
    ├── auth.md     # one node per architectural responsibility
    ├── database.md
    └── ...
```

Each node is a markdown file describing a responsibility, the files it owns, and relevant notes. See [.sade/README.md](.sade/README.md) for the full format.

No JSON manifests. The markdown files are the source of truth.

## Commands

| Command | Description |
|---------|-------------|
| `:SadeInit` | Validate `.sade/`, build file→node index |
| `:SadeSeed` | Use a coding agent to generate initial nodes from the codebase |
| `:SadeAgent` | Invoke agent with current node's context |
| `:SadeTree` | Open the Super Tree |

## Status

Early development. See [DEV-PLAN.md](DEV-PLAN.md) for roadmap.

## License

MIT
