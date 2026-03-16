#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require_relative "../app/db/sqlite"
require_relative "../app/db/vector_store"
require_relative "../app/services/embedding_service"

DevMemory::DB::SQLite.init_schema!
db = DevMemory::DB::SQLite.connection
vector_store = DevMemory::DB::VectorStore.new(db: db)
embedding_service = DevMemory::Services::EmbeddingService.new

rows = db.execute("SELECT * FROM memories")
puts "Reindexing #{rows.length} memories..."

rows.each_with_index do |row, index|
  embedding = embedding_service.embed(row["content"])
  vector_store.upsert(
    memory_id: row["id"],
    embedding: embedding,
    project_id: row["project_id"],
    memory_type: row["memory_type"],
    scope: row["scope"],
    confidence: row["confidence"].to_f,
    tags: JSON.parse(row["tags"] || "[]")
  )
  puts "[#{index + 1}/#{rows.length}] Indexed #{row['id']}"
end

puts "Reindex complete."
