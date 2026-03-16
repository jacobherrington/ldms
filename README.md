# Local Dev Memory System (LDMS)

LDMS is local-first memory for coding with Cursor.

It stores conventions, preferences, and decisions so context gets better over time.

## Start Here (New Developer)

- Read `docs/QUICK_SETUP.md`
- That is the canonical onboarding path (UI-first + global Cursor setup)

## Daily Commands

- `bin/ldms start` - local runtime checks + MCP server
- `bin/ldms ui` - open the LDMS UI
- `bundle exec rake smoke` - handshake check
- `bundle exec rake test` - test suite
- `bundle exec rake preseed` - load curated dev ideas

## Core Flow

1. Start LDMS (`bin/ldms start` for local, or container runtime from quick setup).
2. Use Cursor normally.
3. Save durable lessons:
   - `save_memory` for conventions/preferences
   - `log_decision` for architecture choices

## Make Cursor Respect LDMS

1. Open this folder as the Cursor workspace root (`dev-memory`).
2. Start LDMS before coding (`bin/ldms start` or container runtime).
3. Reload Cursor window after startup so MCP reconnects.
4. In chat, ask Cursor to load context first:
   - `Call get_context_packet for this task before coding.`
5. After finishing meaningful work, store durable guidance:
   - `Call save_memory ...` for conventions/preferences
   - `Call log_decision ...` for architecture decisions

## Make It Global Across Cursor

If you want LDMS respected in every repo (not just this one):

1. Install the global MCP server entry once:
   - `bundle exec rake global_mcp:install`
2. Reload Cursor.
3. In any project chat, use this default opener:
   - `Before coding, call get_context_packet for this task and use it as the primary context.`

Use this to verify global wiring:

- `bundle exec rake global_mcp:print`

Note:
- Global MCP makes LDMS available across repositories.
- Cursor still follows instructions best when you explicitly say context-first at task start.

## Runtime Notes

- Use `LDMS_RUNTIME=docker` for container runtime.
- Open Cursor from the same shell if relying on shell env vars.
- If tools do not appear, reload Cursor window.

## Important Paths

- Profile config: `config/developer_profile.json`
- Local DB: `data/memory.db`
- UI server: `app/ui/server.rb`

## Contributor Guide

- See `CONTRIBUTING.md`
