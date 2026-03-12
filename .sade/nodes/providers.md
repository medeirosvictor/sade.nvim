# Providers

Interface and implementations for external coding agent CLIs. Detects available CLIs, provides unified invocation API.

## Files
- lua/sade/providers/base.lua
- lua/sade/providers/pi.lua
- lua/sade/providers/claude.lua
- lua/sade/providers/codex.lua
- lua/sade/providers/opencode.lua
- lua/sade/providers/ollama.lua
- lua/sade/providers/gemini.lua

## Notes
Provider interface: `id`, `name`, `cmd`, `check`, `build_cmd(ctx_file, prompt)`. Context injection varies by CLI: `--append-system-prompt` (pi, claude), `--instructions` (codex), `--file` (opencode), `-s` (gemini), inline (ollama).
