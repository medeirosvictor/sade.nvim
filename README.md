# sade.nvim

Neovim plugin for live file sync during AI-assisted coding and context-aware agent invocation.

## What It Does

1. **Heartbeat** — Detects external file changes (from coding agents) and refreshes buffers. Shows loading indicators on files being modified in real time.

2. **Super Tree** — A semantic file tree organized by architectural responsibility, not filesystem paths. Files are grouped into nodes based on what they do. Heartbeat ripples show which nodes are being touched.

3. **Context Injection** — Maps the current file to its node and feeds scoped context (node contract + SKILL.md) to the coding agent. The agent gets exactly what it needs without reading the whole codebase.

## Requirements

- Neovim ≥ 0.10
- A `.sade/` directory in your project root
- Optional: [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim) for fuzzy picker UI

## Install

```lua
-- lazy.nvim
{ "medeirosvictor/sade.nvim" }

-- With telescope (optional, for :Sade picker)
{ "medeirosvictor/sade.nvim", dependencies = { "nvim-telescope/telescope.nvim" } }
```

## Quick Start

1. Create a `.sade/` directory in your project root
2. Add `.sade/README.md` (what the project is)
3. Add `.sade/SKILL.md` (coding patterns, constraints)
4. Run `:SadeSeed` to generate initial architecture nodes
5. Run `:SadeAgentSetup` to pick your agent CLI (pi, claude, etc.)
6. Open the Super Tree with `:SadeTree`

## Data

The plugin reads `.sade/` at your project root:

```
.sade/
├── README.md       # guide for this directory
├── SKILL.md        # coding patterns, constraints, agent rules
├── nodes/
│   ├── auth.md     # one node per architectural responsibility
│   ├── database.md
│   └── ...
└── tmp/
    ├── prompts/    # last used prompts
    └── logs/       # agent output logs
```

Each node is a markdown file describing a responsibility, the files it owns, and relevant notes:

```markdown
# Auth

Handles user authentication, sessions, and authorization.

## Files
- src/auth/**
- src/middleware/auth.*

## Notes
- Uses JWT for stateless auth
- Sessions stored in Redis
```

## Commands

| Command | Description |
|---------|-------------|
| `:SadeInit` | Validate `.sade/`, parse nodes, build index |
| `:SadeInfo` | Show status: nodes, indexed files, current file's node |
| `:SadeTree` | Toggle the Super Tree sidebar |
| `:SadeSeed` | Generate seed prompts for initial or additional nodes |
| `:SadePrompt` | Invoke agent with scoped context (adapts to tree/visual/normal) |
| `:SadeSearch` | Search codebase with agent — results go to quickfix list |
| `:SadeSetup` | Pick which agent CLI to use (pi, claude, etc.) |
| `:SadeStop` | Stop all running agent requests |
| `:SadeUpkeep` | Check architecture health (unmapped files, empty nodes) |
| `:Sade` | Show actions picker for current node (improve, compact, unmap) |
| `:SadeHelp` | Show command reference |
| `:SadeGuide` | Show philosophy and workflow guide |

### :SadeUpkeep Options

When running `:SadeUpkeep`, you can:
- `r` — Run agent to fix issues (unmapped files, empty nodes)
- `s` — Simplify/compact nodes (merge similar, reduce verbosity)
- `R` — Rebuild index after manual edits

### :Sade (Node Actions)

Run `:Sade` on a node (or when cursor is on a mapped file) to show an action picker:

- **improve** — Expand description, add notes, clarify responsibilities
- **compact** — Simplify, merge with similar nodes, reduce verbosity  
- **unmap** — Remove files from this node

Uses telescope if available, falls back to vim.ui.select.

## Search

`:SadeSearch` asks the agent to scan the codebase and return relevant locations based on your query. Results go straight to the quickfix list — navigate with `:cnext` / `:cprev`.

- **Scoped by default**: if your current file belongs to a node, the search is scoped to that node's files
- **From Super Tree**: press `s` on a node to search within it
- **Full project**: if no node context, searches the entire project

## Prompt Completions

In the prompt buffer (`:SadePrompt`), you can inject context with special tokens:

| Token | What it injects |
|-------|----------------|
| `#node-name` | The node's contract (e.g., `#heartbeat`) |
| `#skill` | `.sade/SKILL.md` |
| `#readme` | `.sade/README.md` |
| `@path/to/file` | File content (e.g., `@lua/sade/init.lua`) |

Type `#` or `@` and use **Tab** / **Shift-Tab** to navigate the completion popup. References are resolved at submit time and appended as context.

## Super Tree Keymaps

| Key | Description |
|-----|-------------|
| `Enter` / `o` | Expand/collapse node, or open file |
| `a` | Invoke agent on node or file |
| `s` | Search within node → quickfix |
| `A` | Show node actions picker (improve, compact, unmap) |
| `K` | Edit node markdown file |
| `R` | Refresh tree |
| `q` | Close tree |

## Heartbeat

The heartbeat watches for external file changes and shows indicators:

- **Spinning (⠋⠙⠹⠸...)** — File actively being modified (orange, 60s)
- **●** — File was changed, now settled (dim blue)

Commands:
- `:SadeHeartbeatStop` — Stop file watcher
- `:SadeHeartbeatClear` — Clear stale change indicators

## Agent Logs

Agent stdout/stderr are logged to `.sade/tmp/logs/agent.log` for debugging.

## Status

Early development. See [DEV-PLAN.md](DEV-PLAN.md) for roadmap.

## License

MIT
