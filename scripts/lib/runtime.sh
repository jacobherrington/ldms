#!/usr/bin/env bash

if [[ -n "${LDMS_RUNTIME_LIB_LOADED:-}" ]]; then
  return 0
fi
LDMS_RUNTIME_LIB_LOADED=1

ldms_runtime_init() {
  LDMS_ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
  cd "$LDMS_ROOT_DIR"
}

ldms_log() {
  local prefix="${1:-ldms}"
  local message="${2:-}"
  echo "[$prefix] $message"
}

ldms_die() {
  local prefix="${1:-ldms}"
  local message="${2:-fatal error}"
  ldms_log "$prefix" "$message"
  exit 1
}

ldms_command_exists() {
  command -v "$1" >/dev/null 2>&1
}

ldms_ensure_core_commands() {
  local prefix="${1:-ldms}"
  ldms_command_exists ruby || ldms_die "$prefix" "ruby command not found."
  ldms_command_exists bundle || ldms_die "$prefix" "bundler not found. Install with: gem install bundler"
  ldms_command_exists curl || ldms_die "$prefix" "curl command not found."
}

ldms_ensure_data_writable() {
  local prefix="${1:-ldms}"
  mkdir -p data || ldms_die "$prefix" "could not create data directory."
  [[ -w data ]] || ldms_die "$prefix" "data directory is not writable: ${LDMS_ROOT_DIR}/data"
}

ldms_install_bundle_if_needed() {
  local prefix="${1:-ldms}"
  ldms_log "$prefix" "installing gems (if needed)"
  bundle install
}

ldms_init_db() {
  local prefix="${1:-ldms}"
  ldms_log "$prefix" "initializing sqlite schema"
  ruby scripts/init_db.rb
}

ldms_ollama_reachable() {
  curl -s "http://localhost:11434/api/tags" >/dev/null
}

ldms_start_ollama_if_needed() {
  local prefix="${1:-ldms}"
  if ! ldms_ollama_reachable; then
    ldms_log "$prefix" "starting ollama serve in background"
    nohup ollama serve >/tmp/ollama.log 2>&1 &
    sleep 2
  fi
}

ldms_check_or_prepare_ollama() {
  local mode="${1:-}"
  local prefix="${2:-ldms}"

  if ! ldms_command_exists ollama; then
    if [[ "$mode" == "--smoke" ]]; then
      ldms_log "$prefix" "ollama not found; continuing smoke test without embeddings"
      return 0
    fi
    ldms_die "$prefix" "ollama command not found. Install Ollama and run: ollama pull nomic-embed-text"
  fi

  ldms_start_ollama_if_needed "$prefix"

  if ! ldms_ollama_reachable; then
    if [[ "$mode" == "--smoke" ]]; then
      ldms_log "$prefix" "ollama API unavailable; continuing smoke test without embeddings"
      return 0
    fi
    ldms_die "$prefix" "ollama API is not reachable at http://localhost:11434 (start with: ollama serve)"
  fi

  ldms_log "$prefix" "ensuring embedding model"
  local pull_output
  if ! pull_output="$(ollama pull nomic-embed-text 2>&1)"; then
    if [[ "$mode" == "--smoke" ]]; then
      ldms_log "$prefix" "could not pull embedding model; continuing smoke test without embeddings"
      ldms_log "$prefix" "ollama pull error: $(echo "$pull_output" | tr '\n' ' ' | cut -c1-220)"
      return 0
    fi
    ldms_die "$prefix" "failed to pull nomic-embed-text model. Retry: ollama pull nomic-embed-text"
  fi
}

ldms_port_available() {
  local port="$1"
  ruby -rsocket -e '
    port = Integer(ARGV[0])
    hosts = ["0.0.0.0", "::"]
    sockets = []
    begin
      hosts.each { |host| sockets << TCPServer.new(host, port) }
      sockets.each(&:close)
      exit 0
    rescue Errno::EADDRINUSE, Errno::EACCES
      sockets.each { |sock| sock.close rescue nil }
      exit 1
    end
  ' "$port"
}

ldms_resolve_ui_port() {
  if [[ -n "${LDMS_UI_PORT:-}" ]]; then
    echo "$LDMS_UI_PORT"
    return 0
  fi

  local port
  for port in 4567 4568 4569 4570 4571 4572 4573 4574 4575; do
    if ldms_port_available "$port"; then
      echo "$port"
      return 0
    fi
  done

  echo "4567"
}
