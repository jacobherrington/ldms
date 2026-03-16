# LDMS Quick Setup For New Developers

This is the canonical getting-started path.
Goal: get LDMS running, complete onboarding in UI, and enable global Cursor usage.

## Prerequisites

- Docker with `docker compose`
- [Ollama](https://ollama.com)
- Ruby + Bundler (for `bundle exec` commands)

## Container-First Happy Path (Recommended)

From the `dev-memory` directory:

1. Start Ollama and pull the embedding model:
   - `ollama serve`
   - `ollama pull nomic-embed-text`
2. Bootstrap LDMS:
   - `bundle exec rake bootstrap`
3. Set runtime for Cursor MCP:
   - `export LDMS_RUNTIME=docker`
4. Open Cursor from the same shell:
   - `cursor .`
5. Reload Cursor window:
   - Command Palette -> `Developer: Reload Window`
6. Open LDMS UI:
   - `bin/ldms ui`
   - visit `http://localhost:4567`

## First-Run Checklist In UI (No Terminal Needed After Launch)

1. Run one-click smoke in the onboarding banner.
2. Complete the onboarding profile step.
3. Create first memory with onboarding seed.
4. Click **One-click Global Setup** in the onboarding wizard or Quick Actions panel.
   - Runs: doctor -> smoke -> preseed -> global MCP install

## Make Cursor Respect LDMS Globally

After global setup finishes:

1. Reload Cursor.
2. In any project, start tasks with:
   - `Before coding, call get_context_packet for this task and use it as primary context.`
3. Save durable project learnings as you work:
   - `save_memory` for conventions/preferences
   - `log_decision` for architecture choices

## Local Runtime Fallback

If you are not using Docker runtime:

1. `bundle install`
2. `ollama serve`
3. `ollama pull nomic-embed-text`
4. `bin/ldms start`

## Success Criteria

- Smoke returns MCP `initialize` response.
- UI shows onboarding checks and seed succeeds.
- One-click global setup shows all steps as `ok`.
- A first memory appears in the memories list.
