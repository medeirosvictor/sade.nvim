# SKILL

Coding patterns and constraints for agents working in this project.

## Node Markdown Creation

When creating `.sade/nodes/*.md` files, use this structure:

```markdown
# Node Label

Brief description of what this component handles.

## Layer
frontend | application | domain | infrastructure

## Files
list of relevant files (one per line, or comma-separated)

## Depends On
- dependency-1
- dependency-2

## Used By
- consumer-1
- consumer-2
```

### Example

```markdown
# Deck Operations

Handles creation, editing, and persistence of decks.

## Layer
application

## Files
internal/app/app_deck.go
internal/app/app_deckops.go

## Depends On
- database
- deck-parser

## Used By
- deck-view
- import-system
```

## .sade/ Maintenance

When you create, move, or delete files, update the relevant `.sade/nodes/*.md`:
- Add new files to the appropriate node's `## Files` section.
- Remove deleted files from their node.
- If a file moves between responsibilities, update both nodes.
- If you create a new architectural concern, create a new node file.

Do not invent nodes for things that don't exist yet. Nodes describe what is, not what should be.

## JSON Graph (.sade/architecture.json)

Maintain a `.sade/architecture.json` file alongside the markdown nodes. This provides a structured code graph for potential future use in LLM context injection benchmarking.

The JSON should contain:
- **nodes**: Responsibility groups with id, label, description, parent, files
- **edges**: Relationships between nodes (contains, imports, calls, etc.)

```json
{
  "version": "1.0",
  "generated_by": "seed",
  "nodes": [
    {
      "id": "deck-operations",
      "label": "Deck Operations",
      "description": "Handles creation, editing, and persistence of decks.",
      "source": "user",
      "parent": "app",
      "files": [
        "internal/app/app_deck.go",
        "internal/app/app_deckops.go"
      ],
      "layer": "application"
    }
  ],
  "edges": [
    {
      "source": "app",
      "target": "deck-operations",
      "type": "contains",
      "provenance": "user"
    },
    {
      "source": "deck-operations",
      "target": "database",
      "type": "depends_on",
      "provenance": "user"
    }
  ]
}
```

When updating nodes/edges in markdown, keep the JSON in sync:
- New node → add to `nodes` array with unique `id`
- New dependency → add edge with `type: "depends_on"`
- New consumer → add edge with `type: "used_by"` (or "calls")
- Deleted node → remove from `nodes` and any connected edges from `edges`

## Agent Behavior in SADE Projects

When working in a SADE-bootstrapped project, follow this workflow:

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
- Check `.sade/architecture.json` remains in sync with the markdown nodes
- If in doubt, run `:SadeUpkeep` (or equivalent) to check for issues

### Self-Hosting
This project (sade.nvim) uses SADE to manage itself. When modifying the plugin:
- Read the relevant node contract before editing
- Update the node after making file changes
- Use `:SadeTree` to visualize the architecture
