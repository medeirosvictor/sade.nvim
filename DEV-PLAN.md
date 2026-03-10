# Development Plan

Four phases. The plugin is useful after Phase 2.

## How to Work

Sessions are commit boundaries. Complete the session, commit, start fresh. If work bleeds into another session's scope, stop and flag it. Each session produces working code.

---

## Phase 1: Plugin Foundation

Scaffold the plugin, parse node files, build the file→node index.

- [ ] Session 1: Plugin structure + node parsing
  - `lua/sade/` module layout, `plugin/sade.lua` loader
  - `:SadeInit` — find `.sade/` in project root, validate structure
  - Parse `nodes/*.md` — extract description, file list, notes
  - Build file→node index (resolve globs to concrete paths)
  - Query: given a file path, return its node(s)

---

## Phase 2: Heartbeat

Live file sync when coding agents modify files outside Neovim.

- [ ] Session 2: External change detection
  - Watch for file changes via `vim.uv` (libuv fs events)
  - Auto-reload buffers when files change on disk
  - Debounce rapid changes (agents write fast)
  - Sign column indicator on files being modified
  - Configurable debounce window

- [ ] Session 3: Visual feedback
  - Loading spinner in sign column for actively-changing files
  - Clear indicators after writes settle
  - Notification on bulk changes ("12 files updated")

---

## Phase 3: Super Tree

Semantic file navigation by architectural responsibility.

- [ ] Session 4: Tree data + UI
  - Build tree from `nodes/*.md` and their file lists
  - Buffer-based tree view (no external deps)
  - Expand/collapse nodes, open files
  - Heartbeat integration — ripple on nodes with active changes
  - Show node metadata (description, file count)
  - Track unmapped files (on disk but not in any node)

---

## Phase 4: Context Injection

Feed scoped context to coding agents.

- [ ] Session 5: Context assembly + seeding
  - Map current buffer → node via file→node index
  - Assemble context: node markdown + SKILL.md + README.md
  - `:SadeSeed` — prompt an agent to read codebase and generate initial `nodes/*.md`
  - Seed prompt uses README.md + SKILL.md, instructs agent to describe what exists

- [ ] Session 6: Agent invocation
  - `:SadeAgent` — invoke agent with assembled context
  - Support configurable agent CLI (pi, claude, aider, etc.)
  - Yank context to clipboard as fallback
  - Statusline component showing current node name

---

## Session Overview

| Session | Phase | Scope |
|---------|-------|-------|
| 1 | Foundation | Plugin scaffold, node parsing, file→node index |
| 2 | Heartbeat | File watching, buffer reload, sign indicators |
| 3 | Heartbeat | Spinners, settled state, bulk notifications |
| 4 | Super Tree | Tree from nodes, UI, heartbeat ripple |
| 5 | Context | Context assembly, seeding flow |
| 6 | Context | Agent invocation, statusline |

---

## Future

- Telescope/FZF integration for node search
- Git integration (modified files per node)
- sade-app ↔ sade.nvim shared `.sade/`
- Custom prompt templates per node
- Node dependency tracking (which nodes reference each other)
