# SKILL

Coding patterns and constraints for agents working in this project.

## Node Format

When creating or editing `.sade/nodes/*.md` files, use this structure:

```markdown
# Node Label

Brief description of what this component handles.

## Files
- path/to/file.lua
- path/to/other/**

## Notes
Implementation details, constraints, decisions worth remembering.
```

The parser extracts three things:
- **Label + description** — the `# heading` and the paragraph below it
- **Files** — list items under `## Files` (relative paths or globs)
- **Notes** — text under `## Notes`

Only `## Files` is functionally required — it drives the file→node index.
Other `##` sections are ignored by the parser but still visible to agents via raw markdown injection.

### Example

```markdown
# Heartbeat

Watch for external file changes and auto-reload Neovim buffers.

## Files
- lua/sade/heartbeat.lua
- lua/sade/spinner.lua

## Notes
Uses libuv fs_event for recursive directory watching.
Debounces rapid changes before reloading.
```

## .sade/ Maintenance

When you create, move, or delete files, update the relevant `.sade/nodes/*.md`:
- Add new files to the appropriate node's `## Files` section.
- Remove deleted files from their node.
- If a file moves between responsibilities, update both nodes.
- If you create a new architectural concern, create a new node file.

Do not invent nodes for things that don't exist yet. Nodes describe what is, not what should be.

## Agent Behavior

### Before Making Changes
1. Read `.sade/README.md` to understand the project
2. Read `.sade/SKILL.md` for coding patterns
3. Find the relevant node(s) in `.sade/nodes/` that cover the files you're modifying

### While Making Changes
- If you **create** new files, add them to the appropriate node's `## Files` section
- If you **move** files, update both source and target nodes
- If you **delete** files, remove them from the node's `## Files` section
- If you create a **new architectural concern**, create a new node file

### After Making Changes
- Verify the node updates are correct
- If in doubt, run `:SadeUpkeep` to check for unmapped files or empty nodes
