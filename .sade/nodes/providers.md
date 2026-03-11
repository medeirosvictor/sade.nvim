# Providers

Defines the interface and implementations for external coding agent CLIs.

## Responsibilities

- Detect which agent CLIs are available on the system
- Provide a unified interface for invoking different agents
- Handle CLI-specific command building and context injection

## Provider Interface

Each provider implements:
- `id` — unique identifier
- `name` — display name
- `check` — command to check if CLI is installed
- `build_cmd(ctx_file, prompt)` — build the full command with context

## Supported Providers

| Provider | CLI | Context Injection Strategy |
|----------|-----|---------------------------|
| pi | pi | `--append-system-prompt` |
| claude | claude | `--append-system-prompt` |
| codex | opencode | `--instructions` |
| opencode | opencode | `--file` |
| gemini | gemini | `-s` system instruction |
| ollama | ollama | inline prompt |

## Files

- `lua/sade/providers/base.lua` — base provider interface
- `lua/sade/providers/pi.lua` — pi provider
- `lua/sade/providers/claude.lua` — claude provider
- `lua/sade/providers/codex.lua` — codex provider
- `lua/sade/providers/opencode.lua` — opencode provider
- `lua/sade/providers/gemini.lua` — gemini provider
- `lua/sade/providers/ollama.lua` — ollama provider
