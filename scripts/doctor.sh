#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

FAILURES=0

ok() {
  echo "[ok] $1"
}

warn() {
  echo "[warn] $1"
}

fail() {
  echo "[fail] $1"
  FAILURES=$((FAILURES + 1))
}

has_cmd() {
  command -v "$1" >/dev/null 2>&1
}

echo "LDMS doctor"
echo "workspace: $ROOT_DIR"
echo

if has_cmd ruby; then
  ok "ruby: $(ruby -v)"
else
  fail "ruby not found"
fi

if has_cmd bundle; then
  ok "bundler: $(bundle --version)"
else
  fail "bundler not found (install with: gem install bundler)"
fi

if has_cmd curl; then
  ok "curl present"
else
  fail "curl not found"
fi

if has_cmd ollama; then
  ok "ollama present"
else
  warn "ollama not found (embedding tools will fail)"
fi

if mkdir -p data && [[ -w data ]]; then
  ok "data directory writable"
else
  fail "data directory not writable"
fi

if bundle check >/dev/null 2>&1; then
  ok "ruby dependencies installed"
else
  warn "ruby dependencies missing (run: bundle install)"
fi

if has_cmd ollama; then
  if curl -s "http://localhost:11434/api/tags" >/dev/null; then
    ok "ollama API reachable at :11434"
  else
    warn "ollama API not reachable (start: ollama serve)"
  fi
fi

if [[ -f data/memory.db ]]; then
  ok "sqlite db exists at data/memory.db"
else
  warn "sqlite db missing (run: bundle exec rake init_db)"
fi

echo
if [[ "$FAILURES" -gt 0 ]]; then
  echo "doctor result: FAIL ($FAILURES blocking issue(s))"
  exit 1
fi

echo "doctor result: PASS"
