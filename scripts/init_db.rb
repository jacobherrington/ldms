#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require_relative "../app/db/sqlite"

FileUtils.mkdir_p(File.expand_path("../data/vectors", __dir__))
DevMemory::DB::SQLite.init_schema!

puts "Initialized SQLite schema at #{DevMemory::DB::SQLite::DB_PATH}"
