# Spinner

Handles animated spinner display for active operations.

## Responsibilities

- Define spinner animation frames
- Manage timer for animation loop
- Place/remove signs on buffers
- Handle start/stop states with race condition protection

## Features

- Multiple spinner icon sets
- Configurable tick interval
- Thread-safe state management

## Implementation

- `lua/sade/spinner.lua`
