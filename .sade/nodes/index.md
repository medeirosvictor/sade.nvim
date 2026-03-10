# Index

Build and query the file→node reverse index.

## Files
- lua/sade/index.lua
- lua/sade/node_watcher.lua

## Notes
Takes parsed nodes, resolves globs to real file paths, builds a map from filepath to node id(s). Provides query API: given a file path, return its node(s).

## Tests
- tests/test_index.lua
