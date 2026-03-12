# Visual Selection

Visual selection-based agent prompting. Captures selection, shows inline spinner, replaces selection with agent response on completion.

## Files
- lua/sade/ops/visual.lua

## Notes
Uses Neovim extmarks to anchor virtual text spinners at selection boundaries. Direct buffer replacement via `nvim_buf_set_text`. Inspired by ThePrimeagen/99.
