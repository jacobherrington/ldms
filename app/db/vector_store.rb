require "json"
require "time"
require_relative "sqlite"

module DevMemory
  module DB
    class VectorStore
      def initialize(db: SQLite.connection)
        @db = db
      end

      def upsert(memory_id:, embedding:, project_id:, memory_type:, scope:, confidence:, tags:)
        bind_values = [
          memory_id,
          JSON.generate(embedding),
          project_id,
          memory_type,
          scope,
          confidence,
          tags.to_json,
          Time.now.utc.iso8601
        ]

        @db.execute(
          <<~SQL,
            INSERT INTO vectors (memory_id, embedding, project_id, memory_type, scope, confidence, tags, created_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(memory_id) DO UPDATE SET
              embedding = excluded.embedding,
              project_id = excluded.project_id,
              memory_type = excluded.memory_type,
              scope = excluded.scope,
              confidence = excluded.confidence,
              tags = excluded.tags
          SQL
          bind_values
        )
      end

      def search(query_embedding:, project_id: nil, top_k: 5, memory_types: nil)
        candidates = fetch_candidates(project_id: project_id, memory_types: memory_types)

        scored = candidates.map do |row|
          embedding = JSON.parse(row["embedding"])
          similarity = cosine_similarity(query_embedding, embedding)
          {
            memory_id: row["memory_id"],
            similarity: similarity,
            project_id: row["project_id"],
            memory_type: row["memory_type"],
            scope: row["scope"],
            confidence: row["confidence"].to_f,
            tags: parse_json_array(row["tags"])
          }
        end

        scored
          .sort_by { |row| -row[:similarity] }
          .first(top_k)
      end

      private

      def fetch_candidates(project_id:, memory_types:)
        sql = +"SELECT * FROM vectors WHERE 1=1"
        args = []

        if project_id
          sql << " AND project_id = ?"
          args << project_id
        end

        if memory_types && !memory_types.empty?
          placeholders = (["?"] * memory_types.length).join(", ")
          sql << " AND memory_type IN (#{placeholders})"
          args.concat(memory_types)
        end

        @db.execute(sql, args)
      end

      def cosine_similarity(a, b)
        return 0.0 if a.empty? || b.empty? || a.length != b.length

        dot = 0.0
        a_mag = 0.0
        b_mag = 0.0

        a.each_with_index do |value, index|
          av = value.to_f
          bv = b[index].to_f
          dot += av * bv
          a_mag += av * av
          b_mag += bv * bv
        end

        return 0.0 if a_mag.zero? || b_mag.zero?

        dot / Math.sqrt(a_mag * b_mag)
      end

      def parse_json_array(value)
        return [] if value.nil? || value.empty?

        parsed = JSON.parse(value)
        parsed.is_a?(Array) ? parsed : []
      rescue JSON::ParserError
        []
      end
    end
  end
end
