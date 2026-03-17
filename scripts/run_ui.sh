#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/runtime.sh"
ldms_runtime_init

UI_PORT="$(ldms_resolve_ui_port)"
if ! ldms_port_available "$UI_PORT"; then
  echo "[ldms-ui] port $UI_PORT is already in use."
  echo "[ldms-ui] run with another port, for example: LDMS_UI_PORT=4570 bin/ldms"
  exit 1
fi

ldms_ensure_core_commands "ldms-ui"
ldms_ensure_data_writable "ldms-ui"
ldms_install_bundle_if_needed "ldms-ui"
ldms_init_db "ldms-ui"

ldms_log "ldms-ui" "starting UI on http://localhost:${UI_PORT}"
LDMS_UI_PORT="$UI_PORT" bundle exec ruby app/ui/server.rb
