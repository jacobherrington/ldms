require "rake"
require "shellwords"

ROOT = File.expand_path(__dir__)

def run_cmd(command)
  sh(command)
end

desc "Install Ruby dependencies"
task :install do
  run_cmd("bundle install")
end

desc "Initialize SQLite schema"
task :init_db do
  run_cmd("ruby scripts/init_db.rb")
end

desc "Install dependencies and initialize DB"
task setup: %i[install init_db]

desc "Pull Ollama embedding model"
task :ollama do
  run_cmd("ollama pull nomic-embed-text")
end

desc "Preseed curated engineering principles"
task :preseed do
  run_cmd("ruby scripts/preseed_ideas.rb")
end

desc "Run MCP server startup (dev)"
task :dev do
  run_cmd("bash scripts/run.sh")
end

desc "Alias for dev"
task run: :dev

desc "Run local UI server"
task :ui do
  run_cmd("bash scripts/run_ui.sh")
end

desc "Run smoke initialize check"
task :smoke do
  run_cmd("bash scripts/run.sh --smoke")
end

desc "Run local environment diagnostics"
task :doctor do
  run_cmd("bash scripts/doctor.sh")
end

desc "Run essential health checks (doctor + smoke)"
task check: %i[doctor smoke]

desc "Start a local coding session (check + dev)"
task start: %i[check dev]

desc "Print the simplest LDMS command flow"
task :quickstart do
  puts "LDMS quickstart"
  puts "  Container-first: bundle exec rake bootstrap"
  puts "  Local runtime:   bundle exec rake start"
  puts "  Open UI:         bundle exec rake ui"
end

desc "Call context helper (TASK='...', optional PROJECT_ID, TOP_K)"
task :context do
  task_text = ENV["TASK"].to_s
  raise "TASK is required. Example: bundle exec rake context TASK='add auth flow'" if task_text.strip.empty?

  args = [Shellwords.escape(task_text)]
  args << Shellwords.escape(ENV.fetch("PROJECT_ID", ""))
  args << Shellwords.escape(ENV.fetch("TOP_K", "8"))
  run_cmd("bash scripts/context.sh #{args.join(' ')}")
end

desc "Call remember helper (CONTENT='...', optional PROJECT_ID, MEMORY_TYPE, SCOPE, CONFIDENCE, TAGS)"
task :remember do
  content = ENV["CONTENT"].to_s
  raise "CONTENT is required. Example: bundle exec rake remember CONTENT='Use service objects'" if content.strip.empty?

  args = [
    Shellwords.escape(content),
    Shellwords.escape(ENV.fetch("PROJECT_ID", "")),
    Shellwords.escape(ENV.fetch("MEMORY_TYPE", "project_convention")),
    Shellwords.escape(ENV.fetch("SCOPE", "project")),
    Shellwords.escape(ENV.fetch("CONFIDENCE", "0.8")),
    Shellwords.escape(ENV.fetch("TAGS", ""))
  ]
  run_cmd("bash scripts/remember.sh #{args.join(' ')}")
end

namespace :global_mcp do
  desc "Print global MCP config snippet"
  task :print do
    run_cmd("bash scripts/install_global_cursor_mcp.sh --print")
  end

  desc "Install global MCP config entry"
  task :install do
    run_cmd("bash scripts/install_global_cursor_mcp.sh --apply")
  end
end

desc "Run full automated test suite"
task :test do
  run_cmd("ruby test/services/profile_service_test.rb")
  run_cmd("ruby test/services/memory_service_management_test.rb")
  run_cmd("ruby test/services/repo_index_service_test.rb")
  run_cmd("ruby test/services/context_router_service_test.rb")
  run_cmd("ruby test/services/session_service_test.rb")
  run_cmd("ruby test/services/retrieval_service_test.rb")
  run_cmd("ruby test/services/workflow_service_test.rb")
  run_cmd("ruby test/services/kpi_service_test.rb")
  run_cmd("ruby test/services/embedding_service_test.rb")
  run_cmd("ruby test/mcp/server_test.rb")
  run_cmd("ruby test/mcp/tools_test.rb")
  run_cmd("ruby test/ui/server_test.rb")
  run_cmd("ruby test/db/sqlite_schema_test.rb")
end

desc "Run eval quality gates"
task :eval do
  run_cmd("ruby test/evals/retrieval_eval_test.rb")
  run_cmd("ruby test/evals/workflow_eval_test.rb")
end

desc "Build docker images"
task :docker_build do
  run_cmd("docker compose build")
end

desc "Run smoke check in docker"
task :docker_smoke do
  run_cmd("docker compose run --rm ldms-smoke")
end

desc "Run UI in docker compose"
task :docker_ui do
  run_cmd("docker compose up ldms-ui")
end

desc "Container-first bootstrap flow"
task bootstrap: %i[doctor docker_build docker_smoke] do
  puts "[ldms] bootstrap complete"
  puts "[ldms] next: export LDMS_RUNTIME=docker && reload Cursor"
  puts "[ldms] optional UI: bundle exec rake docker_ui"
end
