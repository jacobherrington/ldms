#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

port_available() {
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
  ' "$1"
}

resolve_port() {
  if [[ -n "${LDMS_UI_PORT:-}" ]]; then
    echo "$LDMS_UI_PORT"
    return 0
  fi

  for port in 4567 4568 4569 4570 4571 4572 4573 4574 4575; do
    if port_available "$port"; then
      echo "$port"
      return 0
    fi
  done

  echo "4567"
}

UI_PORT="$(resolve_port)"
if ! port_available "$UI_PORT"; then
  echo "[ldms-ui] port $UI_PORT is already in use."
  echo "[ldms-ui] run with another port, for example: LDMS_UI_PORT=4570 bundle exec rake ui"
  exit 1
fi

echo "[ldms-ui] installing gems (if needed)"
bundle install

echo "[ldms-ui] initializing sqlite schema"
ruby scripts/init_db.rb

echo "[ldms-ui] starting UI on http://localhost:${UI_PORT}"
LDMS_UI_PORT="$UI_PORT" bundle exec ruby app/ui/server.rb
