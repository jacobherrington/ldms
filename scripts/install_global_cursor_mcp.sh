#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GLOBAL_MCP_PATH="${HOME}/.cursor/mcp.json"
MODE="${1:---print}"
SERVER_NAME="${LDMS_GLOBAL_SERVER_NAME:-user-dev-memory-global}"

print_snippet() {
  cat <<EOF
Add this server to your global Cursor MCP config:

{
  "mcpServers": {
    "$SERVER_NAME": {
      "command": "bash",
      "args": ["$ROOT_DIR/scripts/start_mcp.sh"]
    }
  },
  "servers": {
    "$SERVER_NAME": {
      "command": "bash",
      "args": ["$ROOT_DIR/scripts/start_mcp.sh"]
    }
  }
}

Suggested file: $GLOBAL_MCP_PATH
EOF
}

apply_global_config() {
  mkdir -p "$(dirname "$GLOBAL_MCP_PATH")"

  if [[ -f "$GLOBAL_MCP_PATH" ]]; then
    cp "$GLOBAL_MCP_PATH" "${GLOBAL_MCP_PATH}.bak"
    echo "[ldms] backup created at ${GLOBAL_MCP_PATH}.bak"
  fi

  ruby -rjson -e '
path = ARGV[0]
server_script = ARGV[1]

config = if File.exist?(path)
  JSON.parse(File.read(path))
else
  {}
end

server_name = ARGV[2]
legacy_name = "dev-memory-global"

config["mcpServers"] ||= {}
config["servers"] ||= {}
entry = {
  "command" => "bash",
  "args" => [server_script]
}
config["mcpServers"][server_name] = entry
config["servers"][server_name] = entry

if server_name != legacy_name
  config["mcpServers"].delete(legacy_name)
  config["servers"].delete(legacy_name)
end

File.write(path, JSON.pretty_generate(config) + "\n")
puts "[ldms] wrote global MCP config: #{path}"
' "$GLOBAL_MCP_PATH" "$ROOT_DIR/scripts/start_mcp.sh" "$SERVER_NAME"

  echo "[ldms] server name: $SERVER_NAME"
  echo "[ldms] done. Reload Cursor to pick up global server."
}

case "$MODE" in
  --print)
    print_snippet
    ;;
  --apply)
    apply_global_config
    ;;
  *)
    echo "Usage: scripts/install_global_cursor_mcp.sh [--print|--apply]"
    exit 1
    ;;
esac
