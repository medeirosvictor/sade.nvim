# Index

Build and query the file→node reverse index.

## Files
- lua/sade/index.lua

## Notes
Takes parsed nodes, resolves globs to real file paths, builds a map from filepath to node id(s). Provides query API: given a file path, return its node(s).
