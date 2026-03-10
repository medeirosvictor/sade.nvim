-- Pre-made prompts for sade operations
-- Used by seed, upkeep, and agent operations

local M = {}

--- Prompt for initial seed (creating nodes from scratch)
M.seed = [[Your task is to describe the architecture of this codebase by creating node files.

Each node represents one architectural responsibility — a group of files that work together toward a shared purpose.
Nodes are NOT folders. A node groups files by what they DO, not where they live.

Create one markdown file per node in `.sade/nodes/` with this format:

```markdown
# Node Name

Brief description of what this node owns and how it works.

## Files
- path/to/file.lua
- path/to/other/**

## Notes
Any implementation details, constraints, or decisions worth documenting.
```

Guidelines:
- Describe what EXISTS in the codebase. Don't invent architecture that isn't there.
- A file can belong to multiple nodes if it genuinely bridges concerns.
- Use glob patterns (e.g. `src/auth/**`) when a whole directory belongs to one node.
- Keep descriptions concise and concrete.
- Name node files in kebab-case: `auth.md`, `database.md`, `api-routes.md`.

Output each node as a code block prefixed with its filename:

`nodes/auth.md`
```markdown
# Auth
...
```
]]

--- Prompt for reseeding only unmapped files
M.reseed = [[Your task is to add unmapped files to the architectural node files in `.sade/nodes/`.

Some files in the codebase are not yet assigned to any node. You need to either:
1. Add these files to existing nodes where they fit, OR
2. Create new nodes for them if they represent a new architectural responsibility.

A file can remain unmapped if it truly doesn't fit anywhere (e.g., dead code, generated files, or files that need team review).

Edit existing node markdown files in `.sade/nodes/` to add the unmapped files to their `## Files` sections.

Node format:
```markdown
# Node Name

Brief description of what this node owns.

## Files
- path/to/file.lua
- path/to/other/**

## Notes
Implementation details...
```
]]

--- Prompt for upkeep/refresh (fix empty nodes and unmapped files)
M.upkeep = [[Your task is to update the architectural node files in `.sade/nodes/` to reflect the current state of the codebase.
]]

--- Prompt for simplifying/compacting nodes
M.simplify = [[Your task is to simplify and consolidate the architectural node files in `.sade/nodes/`.

Review each node and:
1. **Merge similar nodes** - If two nodes have overlapping responsibilities, merge them into one
2. **Remove redundant patterns** - Simplify glob patterns, remove duplicates
3. **Condense descriptions** - Make descriptions more concise
4. **Unmap orphaned files** - If files don't meaningfully belong to any node, remove them from the `## Files` sections (don't delete the files, just unmap them)

Goal: Fewer, cleaner nodes that still cover all meaningful code in the project.

Node format:
```markdown
# Node Name

Brief description.

## Files
- path/to/file.lua
- path/to/other/**

## Notes
Optional notes.
```

Output each updated node as a code block prefixed with its filename.
]]

--- Prompt for improving a specific node
M.improve_node = [[Your task is to improve the architectural node file at `{node_path}`.

The node currently contains:
```
{node_content}
```

Please:
1. Expand the description with more details about what this node owns
2. Add implementation notes or constraints in the `## Notes` section
3. Review the file patterns - add any missing related files
4. Add any helpful context for developers working in this area

Output the improved node as a code block:
]]

--- Prompt for compacting/simplifying a specific node
M.compact_node = [[Your task is to simplify and compact the architectural node file at `{node_path}`.

The node currently contains:
```
{node_content}
```

Please:
1. Condense the description to be more concise
2. Simplify file patterns (use globs where possible, remove redundancies)
3. Reduce or remove the Notes section if not critical
4. Consider if this node should be merged with another similar node

Output the simplified node as a code block, or indicate if it should be merged with another node.
]]

--- Prompt for unmapping/removing files from a node
M.unmap_node = [[Your task is to remove files from the architectural node file at `{node_path}`.

The node currently contains:
```
{node_content}
```

The following files should be unmapped (removed from this node):
```
{files_to_unmap}
```

Please update the node's `## Files` section to remove these files. If the file was glob patterns, adjust accordingly.

Output the updated node as a code block:
]]

--- Prompt for analyzing a file to find its best node(s)
M.analyze_file = [[Your task is to analyze a file in this codebase and determine which architectural node(s) it belongs to.

## File to analyze
`{file_path}`

```
{file_content}
```

## Current Architecture

The codebase has the following nodes in `.sade/nodes/`:

{node_summaries}

## Your task

1. Read the file content above
2. Compare it against each node's description and existing files
3. Determine which node(s) this file belongs to, or if it needs a new node

Output your analysis as:

### Classification
**Recommended node(s):** `node-name` (or "new node" / "unmapped")

### Reasoning
Brief explanation of why this file belongs to the recommended node(s).

### If new node needed
If you believe a new node is needed, provide:
- **Node name:** (kebab-case)
- **Description:** (what this node would own)
- **Suggested files:** (this file + any related files that should also belong)
]]

--- Prompt for reclassifying/remapping a file to a different node
M.reclassify_file = [[Your task is to reclassify a file from one architectural node to another (or to create a new node for it).

## File to reclassify
`{file_path}`

Current node(s): `{current_nodes}`

```
{file_content}
```

## Current Architecture

{node_summaries}

## Your task

1. Analyze the file and compare against all nodes
2. Determine the best node(s) for this file
3. Update the node files accordingly:
   - Remove the file from its current node(s)
   - Add it to the new recommended node(s), OR
   - Create a new node if none fit

If the file should remain unmapped, explain why.

Output your analysis and the updated node files.
]]

--- Prompt for evaluating the entire codebase health
M.evaluate = [[Your task is to evaluate the overall architecture health of this codebase.

## Current state
- Nodes: {node_count}
- Indexed files: {file_count}
- Unmapped files: {unmapped_count}

## Your task

Review the architecture and provide:

### Health Score
Rate from 1-10 with brief justification.

### Strengths
What is working well?

### Issues
What problems exist? (empty nodes, overlapping responsibilities, unclear boundaries, etc.)

### Recommendations
Priority list of improvements.

### Node Analysis
For each node, briefly assess:
- Is the description clear?
- Are the file patterns correct?
- Does it have the right boundaries?
]]

return M
