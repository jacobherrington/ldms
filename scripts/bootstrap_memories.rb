#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "../app/db/sqlite"
require_relative "../app/services/bootstrap_service"

DevMemory::DB::SQLite.init_schema!

project_id = ENV["LDMS_PROJECT_ID"] || File.basename(Dir.pwd)
result = DevMemory::Services::BootstrapService.new(project_id: project_id).run

puts "Bootstrap complete for project `#{result[:project_id]}`"
puts "Created: #{result[:created_count]} | Skipped: #{result[:skipped_count]}"
