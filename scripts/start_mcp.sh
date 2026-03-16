#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

runtime_mode="${LDMS_RUNTIME:-auto}"

has_bundle() {
  command -v bundle >/dev/null 2>&1
}

has_docker_compose() {
  docker compose version >/dev/null 2>&1
}

if [[ "$runtime_mode" == "docker" ]]; then
  if ! has_docker_compose; then
    echo "[ldms] LDMS_RUNTIME=docker but docker compose is unavailable" >&2
    exit 1
  fi
  exec docker compose run --rm -T ldms-mcp
fi

if [[ "$runtime_mode" == "local" ]]; then
  if ! has_bundle; then
    echo "[ldms] LDMS_RUNTIME=local but bundler is unavailable" >&2
    exit 1
  fi
  exec bundle exec ruby app/mcp/server.rb
fi

if has_bundle; then
  exec bundle exec ruby app/mcp/server.rb
fi

if has_docker_compose; then
  exec docker compose run --rm -T ldms-mcp
fi

echo "[ldms] Could not find local bundler or docker compose runtime" >&2
exit 1
