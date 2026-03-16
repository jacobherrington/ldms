#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

CONTENT="${1:-}"
PROJECT_ID="${2:-$(basename "$ROOT_DIR")}"
MEMORY_TYPE="${3:-project_convention}"
SCOPE="${4:-project}"
CONFIDENCE="${5:-0.8}"
TAGS="${6:-}"

if [[ -z "$CONTENT" ]]; then
  echo "Usage: scripts/remember.sh \"content\" [project_id] [memory_type] [scope] [confidence] [comma_tags]"
  exit 1
fi

REQUEST_JSON="$(ruby -rjson -e '
  content = ARGV[0]
  project_id = ARGV[1]
  memory_type = ARGV[2]
  scope = ARGV[3]
  confidence = ARGV[4].to_f
  tags = ARGV[5].to_s.split(",").map(&:strip).reject(&:empty?)

  req = {
    jsonrpc: "2.0",
    id: 1,
    method: "tools/call",
    params: {
      name: "save_memory",
      arguments: {
        content: content,
        project_id: project_id,
        memory_type: memory_type,
        scope: scope,
        confidence: confidence,
        tags: tags
      }
    }
  }

  puts JSON.generate(req)
' "$CONTENT" "$PROJECT_ID" "$MEMORY_TYPE" "$SCOPE" "$CONFIDENCE" "$TAGS")"

printf "%s\n" "$REQUEST_JSON" | ruby app/mcp/server.rb
