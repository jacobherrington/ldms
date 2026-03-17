#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

runtime_mode="${LDMS_RUNTIME:-auto}"

has_bundle() {
  command -v bundle >/dev/null 2>&1
}

if [[ "$runtime_mode" == "docker" ]]; then
  echo "[ldms] LDMS_RUNTIME=docker is no longer supported in this minimal build" >&2
  exit 1
fi

if has_bundle; then
  exec bundle exec ruby app/mcp/server.rb
fi

echo "[ldms] bundler not found; install with: gem install bundler" >&2
exit 1
