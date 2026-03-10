# Parser

Parse node markdown files into structured Lua tables.

## Files
- lua/sade/parser.lua

## Notes
Reads a single `nodes/*.md` file. Extracts id (from filename), description (first paragraph after heading), file list (`## Files` section), and notes (`## Notes` section).

## Tests
- tests/test_parser.lua
