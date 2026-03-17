# Local Dev Memory System (LDMS)

Local-first memory for Cursor coding.  
It stores preferences, conventions, and decisions so context gets better over time.

## 5-Minute Start

1. From this folder, run:
   - `bin/ldms install`
2. Start LDMS UI:
   - `bin/ldms`
3. Open the UI URL shown in terminal.
4. Reload Cursor window once.
5. In chat, verify:
   - `Call get_dev_profile`

## Daily Flow

1. Start LDMS with `bin/ldms`
2. Ask Cursor to run task-aware preflight context before larger tasks:
   - `Call begin_task_context with task "..." and task_type "auto"`
   - `task_type` options: `feature`, `bugfix`, `refactor`, `docs`, `test`, `ops`, `auto`
3. (Optional) Use low-level context packet for debugging:
   - `Call get_context_packet with task "..."`
4. After implementation, run post-task review persistence:
   - `Call process_task_review with task "..." and review_text "..."`
5. Save useful patterns/decisions directly when needed:
   - `Call save_memory ...`
   - `Call log_decision ...`

Or use one command from terminal for local flow:
- `bin/ldms task --task "implement feature X"`
- Optional autosave pass: add `--review-file /path/to/review.txt`

### Task Type Examples

- Feature: `Call begin_task_context with task "add billing retry flow" and task_type "feature"`
- Bugfix: `Call begin_task_context with task "fix websocket reconnect regression" and task_type "bugfix"`
- Refactor: `Call begin_task_context with task "refactor memory ranking into smaller methods" and task_type "refactor"`
- Docs: `Call begin_task_context with task "document global MCP setup" and task_type "docs"`
- Test: `Call begin_task_context with task "add regression test for fallback search" and task_type "test"`
- Ops: `Call begin_task_context with task "stabilize CI startup checks" and task_type "ops"`

## Global Mode (Any Project)

1. Install global MCP entry:
   - `bin/ldms global-install`
2. Reload Cursor.
3. In any workspace, verify:
   - `Call get_dev_profile`

## Commands

- `bin/ldms install` - one-command setup + doctor + bootstrap
- `bin/ldms` or `bin/ldms up` - start UI-first mode
- `bin/ldms task` - run task preflight and optional post-task memory loop
- `bin/ldms start` - doctor + smoke + MCP server
- `bin/ldms dev` - MCP server only
- `bin/ldms ui` - UI only
- `bin/ldms check` - doctor + smoke
- `bin/ldms bootstrap` - seed starter project memories
- `bin/ldms test` - test suite
- `bin/ldms global-install` - install global Cursor MCP entry
- `bin/ldms global-print` - print global MCP snippet

## Core MCP Tools

- `get_dev_profile`
- `search_memory`
- `begin_task_context`
- `get_context_packet`
- `save_memory`
- `process_task_review`
- `seed_developer_memories`
- `log_decision`

### Seed Developer Principles

You can quickly seed curated memory from developer influences:

- `Call seed_developer_memories with developers ["sandi metz", "kent beck"]`
- Optional args: `project_id`, `scope`, `confidence`
- Current presets: `dhh`, `sandi metz`, `martin fowler`, `kent beck`, `aaron patterson`, `obie fernandez`

## Notes

- If tools do not appear, reload Cursor window.
- If port `4567` is busy, LDMS picks the next open port.
- Docker runtime is not supported in this minimal build.
