#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

TASK="${1:-}"
PROJECT_ID="${2:-$(basename "$ROOT_DIR")}"
TOP_K="${3:-8}"

if [[ -z "$TASK" ]]; then
  echo "Usage: scripts/context.sh \"task description\" [project_id] [top_k]"
  exit 1
fi

REQUEST_JSON="$(ruby -rjson -e '
  task = ARGV[0]
  project_id = ARGV[1]
  top_k = ARGV[2].to_i

  req = {
    jsonrpc: "2.0",
    id: 1,
    method: "tools/call",
    params: {
      name: "get_context_packet",
      arguments: {
        task: task,
        project_id: project_id,
        top_k: top_k
      }
    }
  }

  puts JSON.generate(req)
' "$TASK" "$PROJECT_ID" "$TOP_K")"

printf "%s\n" "$REQUEST_JSON" | ruby app/mcp/server.rb
