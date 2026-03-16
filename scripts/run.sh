#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

MODE="${1:-}"

log() {
  echo "[ldms] $1"
}

die() {
  log "$1"
  exit 1
}

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

ensure_core_commands() {
  command_exists ruby || die "ruby command not found."
  command_exists bundle || die "bundler not found. Install with: gem install bundler"
  command_exists curl || die "curl command not found."
}

check_data_writable() {
  mkdir -p data || die "could not create data directory."
  [[ -w data ]] || die "data directory is not writable: $ROOT_DIR/data"
}

ollama_reachable() {
  curl -s "http://localhost:11434/api/tags" >/dev/null
}

start_ollama_if_needed() {
  if ! ollama_reachable; then
    log "starting ollama serve in background"
    nohup ollama serve >/tmp/ollama.log 2>&1 &
    sleep 2
  fi
}

check_or_prepare_ollama() {
  if ! command_exists ollama; then
    if [[ "$MODE" == "--smoke" ]]; then
      log "ollama not found; continuing smoke test without embeddings"
      return 0
    fi
    die "ollama command not found. Install Ollama and run: ollama pull nomic-embed-text"
  fi

  start_ollama_if_needed

  if ! ollama_reachable; then
    if [[ "$MODE" == "--smoke" ]]; then
      log "ollama API unavailable; continuing smoke test without embeddings"
      return 0
    fi
    die "ollama API is not reachable at http://localhost:11434 (start with: ollama serve)"
  fi

  log "ensuring embedding model"
  if ! pull_output="$(ollama pull nomic-embed-text 2>&1)"; then
    if [[ "$MODE" == "--smoke" ]]; then
      log "could not pull embedding model; continuing smoke test without embeddings"
      log "ollama pull error: $(echo "$pull_output" | tr '\n' ' ' | cut -c1-220)"
      return 0
    fi
    die "failed to pull nomic-embed-text model. Retry: ollama pull nomic-embed-text"
  fi
}

preflight() {
  ensure_core_commands
  check_data_writable
}

preflight

log "installing gems (if needed)"
bundle install

check_or_prepare_ollama

log "initializing sqlite schema"
ruby scripts/init_db.rb

if [[ "$MODE" == "--smoke" ]]; then
  log "running MCP initialize smoke test"
  printf '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}\n' | ruby app/mcp/server.rb
  log "smoke test complete"
  exit 0
fi

log "starting MCP server (Ctrl+C to stop)"
ruby app/mcp/server.rb
