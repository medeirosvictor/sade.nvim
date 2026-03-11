# Prompt Buffer

Handles the interactive prompt buffer for multi-line prompts.

## Responsibilities

- Open a dedicated buffer for composing prompts
- Support multi-line prompts with markdown rendering
- Handle submit (`:w` + `:q`) and cancel (Escape) workflows
- Manage buffer lifecycle (open/close)

## Usage

```
:SadePrompt
```

Opens a prompt buffer. Write and quit to submit, Escape to cancel.

## Implementation

- `lua/sade/prompt.lua`
