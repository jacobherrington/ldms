#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GLOBAL_MCP_PATH="${HOME}/.cursor/mcp.json"
MODE="${1:---print}"

print_snippet() {
  cat <<EOF
Add this server to your global Cursor MCP config:

{
  "servers": {
    "dev-memory-global": {
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

config["servers"] ||= {}
config["servers"]["dev-memory-global"] = {
  "command" => "bash",
  "args" => [server_script]
}

File.write(path, JSON.pretty_generate(config) + "\n")
puts "[ldms] wrote global MCP config: #{path}"
' "$GLOBAL_MCP_PATH" "$ROOT_DIR/scripts/start_mcp.sh"

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
