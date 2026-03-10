# UI

Shared UI primitives for modal popups, selection dialogs, and floating windows.

## Files
- lua/sade/ui.lua

## Notes
`popup()` creates a centered floating window with rounded border, title, and q/Esc to close. `select()` builds on popup to create a numbered selection list with Enter/number-key picking. Used by SadeHelp, SadeGuide, and SadeAgentSetup.
