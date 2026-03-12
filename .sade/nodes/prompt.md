# Prompt Buffer

Interactive prompt buffer for composing multi-line prompts with `#node` and `@file` completions. Supports submit via `:w`/Enter and cancel via Escape/q.

## Files
- lua/sade/prompt.lua
- lua/sade/completions.lua

## Notes
- `#node-name` injects a node contract, `#skill` / `#readme` inject SKILL.md / README.md
- `@path/to/file` injects file content wrapped in a code block
- Completions use native `vim.fn.complete()` with debounced `TextChangedI`
- References are resolved at submit time via `completions.resolve_prompt()`
