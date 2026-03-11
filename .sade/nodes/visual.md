# Visual Selection

Handles visual selection-based agent prompting, inspired by ThePrimeagen/99.

## Responsibilities

- Capture visual selection range from the current buffer
- Place extmarks to track selection during agent execution
- Show inline spinner using virtual text
- Stream agent output to the buffer
- Replace selection with agent response on completion

## Usage

1. Select code in visual mode
2. Run `:SadePrompt`
3. Enter your prompt
4. Agent processes selection and replaces it

## Implementation Details

- Uses Neovim extmarks to anchor virtual text
- Spinner animation via timer
- Direct buffer text replacement via `nvim_buf_set_text`

## Inspiration

Inspired by ThePrimeagen/99 - https://github.com/ThePrimeagen/99

## Files

- `lua/sade/ops/visual.lua`
