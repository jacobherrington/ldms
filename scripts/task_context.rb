#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "optparse"
require_relative "../app/db/sqlite"
require_relative "../app/services/retrieval_service"
require_relative "../app/services/memory_loop_service"

options = {
  task_type: "auto",
  top_k: 8,
  auto_save_threshold: DevMemory::Services::MemoryLoopService::DEFAULT_AUTO_SAVE_THRESHOLD,
  scope: "project",
  format: "text"
}

OptionParser.new do |parser|
  parser.banner = "Usage: ruby scripts/task_context.rb --task \"...\" [options]"
  parser.on("--task TASK", "Task description (required)") { |value| options[:task] = value }
  parser.on("--task-type TYPE", "Task type: feature|bugfix|refactor|docs|test|ops|auto") { |value| options[:task_type] = value }
  parser.on("--project-id ID", "Project identifier (defaults to workspace name)") { |value| options[:project_id] = value }
  parser.on("--top-k N", Integer, "Number of memories to retrieve (default 8)") { |value| options[:top_k] = value }
  parser.on("--review-file PATH", "Optional file containing post-task review bullets") { |value| options[:review_file] = value }
  parser.on("--auto-save-threshold N", Float, "Auto-save threshold (default 0.85)") { |value| options[:auto_save_threshold] = value }
  parser.on("--scope SCOPE", "Memory scope for persisted candidates (default project)") { |value| options[:scope] = value }
  parser.on("--json", "Print machine-readable JSON output") { options[:format] = "json" }
end.parse!

abort("Missing required argument --task") if options[:task].to_s.strip.empty?

DevMemory::DB::SQLite.init_schema!
workspace_root = Dir.pwd
project_id = options[:project_id].to_s.strip
project_id = ENV["LDMS_PROJECT_ID"].to_s.strip if project_id.empty?
project_id = File.basename(workspace_root) if project_id.empty?

retrieval = DevMemory::Services::RetrievalService.new
task_context = retrieval.build_task_context(
  task: options[:task],
  project_id: project_id,
  task_type: options[:task_type],
  top_k: options[:top_k]
)

review_result = nil
if options[:review_file]
  review_text = File.read(options[:review_file])
  memory_loop = DevMemory::Services::MemoryLoopService.new
  review_result = memory_loop.process_task_review(
    task: options[:task],
    project_id: project_id,
    review_text: review_text,
    task_type: options[:task_type],
    scope: options[:scope],
    auto_save_threshold: options[:auto_save_threshold]
  )
end

if options[:format] == "json"
  puts JSON.pretty_generate(
    task_context: task_context,
    review_result: review_result
  )
  exit 0
end

puts "[ldms-task] project: #{project_id}"
puts "[ldms-task] task_type: #{task_context[:task_type]}"
puts "[ldms-task] preflight context loaded"
puts
puts "Conventions:"
task_context.dig(:working_context, :conventions).each { |item| puts "- #{item}" }
puts "Decisions:"
task_context.dig(:working_context, :decisions).each { |item| puts "- #{item}" }
puts "Pitfalls:"
task_context.dig(:working_context, :pitfalls).each { |item| puts "- #{item}" }
puts
puts "Post-task review template:"
puts "- Convention: ..."
puts "- Pattern: ..."
puts "- Pitfall: ..."
puts "- Decision: ..."
puts
if review_result
  puts "[ldms-task] review processed"
  puts "Saved: #{review_result[:saved_count]}, Suggested: #{review_result[:suggestion_count]}"
else
  puts "[ldms-task] optional: provide --review-file to persist durable memories."
end
