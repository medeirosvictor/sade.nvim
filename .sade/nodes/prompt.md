# Prompt Buffer

Handles the interactive prompt buffer for multi-line prompts, with `#node` and `@file` completions.

## Responsibilities

- Open a dedicated buffer for composing prompts
- Support multi-line prompts with markdown rendering
- Handle submit (`:w` / Enter) and cancel (Escape / q) workflows
- Manage buffer lifecycle (open/close)
- Provide `#node` and `@file` completions in the prompt buffer
- Resolve references at submit time (append injected context)

## Files
- lua/sade/prompt.lua
- lua/sade/completions.lua

## Notes
- `#node-name` injects a node contract, `#skill` / `#readme` inject SKILL.md / README.md
- `@path/to/file` injects file content wrapped in a code block
- Completions use native `vim.fn.complete()` with debounced `TextChangedI`
- References are resolved at submit time via `completions.resolve_prompt()`
