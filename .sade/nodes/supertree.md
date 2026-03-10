# Super Tree

Semantic file tree organized by architectural responsibility. Data model and buffer-based UI.

## Files
- lua/sade/supertree.lua
- lua/sade/supertree_ui.lua

## Notes
`supertree.lua` builds a flat entry list from the index — nodes, their files (when expanded), and unmapped files. Entries carry heartbeat active state. `supertree_ui.lua` renders entries into a left-split scratch buffer with expand/collapse (CR/o), file open in previous window, node preview (K), and periodic refresh for heartbeat ripple. No external dependencies.

## Tests
- tests/test_supertree.lua
