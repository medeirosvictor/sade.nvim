# Agent

Agent CLI detection, configuration, and invocation. Bridges SADE context to external coding agents via a provider system.

## Files
- lua/sade/agent.lua
- lua/sade/tracking.lua
- lua/sade/prompts.lua

## Notes
Each provider in `providers/` defines how to invoke its CLI with context. `agent.lua` loads all providers, detects which are installed, and handles invocation. Provider interface: `id`, `name`, `cmd`, `check`, `build_cmd(ctx_file, prompt)`. Context injection strategy varies by CLI: `--append-system-prompt` (pi, claude), `--instructions` (codex), `--file` (opencode), `-s` system instruction (gemini), inline prompt (ollama).

## Tests
- tests/test_agent.lua
