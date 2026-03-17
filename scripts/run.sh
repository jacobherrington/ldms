#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/runtime.sh"
ldms_runtime_init

MODE="${1:-}"
ldms_ensure_core_commands "ldms"
ldms_ensure_data_writable "ldms"
ldms_install_bundle_if_needed "ldms"
ldms_check_or_prepare_ollama "$MODE" "ldms"
ldms_init_db "ldms"

if [[ "$MODE" == "--smoke" ]]; then
  ldms_log "ldms" "running MCP initialize smoke test"
  printf '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}\n' | ruby app/mcp/server.rb
  ldms_log "ldms" "smoke test complete"
  exit 0
fi

ldms_log "ldms" "starting MCP server (Ctrl+C to stop)"
ruby app/mcp/server.rb
