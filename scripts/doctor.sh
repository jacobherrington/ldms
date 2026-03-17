#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

FAILURES=0
WARNINGS=0

ok() {
  echo "[ok] $1"
}

warn() {
  echo "[warn] $1"
  WARNINGS=$((WARNINGS + 1))
}

fail() {
  echo "[fail] $1"
  FAILURES=$((FAILURES + 1))
}

has_cmd() {
  command -v "$1" >/dev/null 2>&1
}

print_fix() {
  echo "      fix: $1"
}

ruby_eval() {
  ruby -e "$1"
}

echo "LDMS doctor"
echo "workspace: $ROOT_DIR"
echo

if has_cmd ruby; then
  ok "ruby: $(ruby -v)"
else
  fail "ruby not found"
  print_fix "Install Ruby 3.2+ and rerun doctor."
fi

if has_cmd bundle; then
  ok "bundler: $(bundle --version)"
else
  fail "bundler not found (install with: gem install bundler)"
  print_fix "Run: gem install bundler"
fi

if has_cmd curl; then
  ok "curl present"
else
  fail "curl not found"
  print_fix "Install curl and rerun doctor."
fi

if has_cmd ollama; then
  ok "ollama present"
else
  warn "embedding availability: degraded (ollama command missing)"
  print_fix "Install Ollama and run: ollama serve"
fi

if mkdir -p data && [[ -w data ]]; then
  ok "db writability: pass (data directory writable)"
else
  fail "db writability: fail (data directory not writable)"
  print_fix "Ensure '$ROOT_DIR/data' is writable by your user."
fi

if bundle check >/dev/null 2>&1; then
  ok "ruby dependencies installed"
else
  warn "ruby dependencies missing (run: bundle install)"
  print_fix "Run: bundle install"
fi

if has_cmd ollama; then
  if curl -s "http://localhost:11434/api/tags" >/dev/null; then
    ok "embedding availability: pass (ollama API reachable at :11434)"
  else
    warn "embedding availability: degraded (ollama API unreachable at :11434)"
    print_fix "Run: ollama serve"
  fi
fi

if [[ -f data/memory.db ]]; then
  ok "sqlite db exists at data/memory.db"
else
  warn "sqlite db missing (run: bin/ldms setup)"
  print_fix "Run: ruby scripts/init_db.rb"
fi

if [[ -f ".cursor/mcp.json" ]]; then
  ok "mcp readiness: pass (.cursor/mcp.json found)"
else
  fail "mcp readiness: fail (.cursor/mcp.json missing)"
  print_fix "Create .cursor/mcp.json or run: bin/ldms global-install"
fi

if [[ -f data/memory.db ]]; then
  mismatch_counts="$(ruby_eval 'require "sqlite3"; db=SQLite3::Database.new("data/memory.db"); db.results_as_hash=true; orphan_vectors=db.get_first_value("SELECT COUNT(*) FROM vectors v LEFT JOIN memories m ON m.id=v.memory_id WHERE m.id IS NULL").to_i; missing_vectors=db.get_first_value("SELECT COUNT(*) FROM memories m LEFT JOIN vectors v ON v.memory_id=m.id WHERE v.memory_id IS NULL AND COALESCE(m.is_archived,0)=0").to_i; puts "#{orphan_vectors},#{missing_vectors}"' 2>/dev/null || true)"
  if [[ -n "$mismatch_counts" ]]; then
    orphan_vectors="${mismatch_counts%%,*}"
    missing_vectors="${mismatch_counts##*,}"
    if [[ "$orphan_vectors" == "0" && "$missing_vectors" == "0" ]]; then
      ok "vector consistency: pass (no mismatches)"
    else
      warn "vector consistency: degraded (orphan_vectors=$orphan_vectors, missing_vectors=$missing_vectors)"
      print_fix "Run: ruby scripts/reindex.rb"
    fi
  else
    warn "vector consistency: skipped (could not query sqlite)"
  fi
fi

echo
if [[ "$FAILURES" -gt 0 ]]; then
  echo "doctor result: FAIL ($FAILURES blocking issue(s), $WARNINGS warning(s))"
  exit 1
fi

if [[ "$WARNINGS" -gt 0 ]]; then
  echo "doctor result: PASS WITH WARNINGS ($WARNINGS)"
else
  echo "doctor result: PASS"
fi
