# LDMS Quick Setup

Use this when you want LDMS running fast.

## Prereqs

- Ruby 3.2+
- Bundler
- Ollama running locally

## Setup + Run

From `dev-memory`:

1. `bin/ldms setup`
2. `bin/ldms`
3. Open the UI URL shown in terminal.
4. Reload Cursor window.

## Verify In Cursor

Run these in chat:

1. `Call get_dev_profile`
2. `Call save_memory with content "ldms quick check", memory_type "project_convention", scope "project"`
3. `Call search_memory with query "ldms quick check", top_k 3`
4. `Call get_context_packet with task "implement feature X"`

## Global (All Projects)

1. `bin/ldms global-install`
2. Reload Cursor
3. In any workspace: `Call get_dev_profile`

## If Something Looks Off

- Tools missing: reload Cursor window.
- UI port conflict: set `LDMS_UI_PORT=4570` and rerun `bin/ldms`.
- Health check: run `bin/ldms check`.
