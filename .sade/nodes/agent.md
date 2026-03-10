# Agent

Agent CLI detection, configuration, and invocation. Bridges SADE context to external coding agents.

## Files
- lua/sade/agent.lua

## Notes
Detects available agent CLIs (pi, claude) via version checks. User picks one via `:SadeAgentSetup`. `:SadeAgent` assembles context for the current file or a Super Tree node, writes it to a temp file, copies to clipboard, and opens the agent in a toggleterm float. Falls back to a plain terminal split if toggleterm isn't installed.
