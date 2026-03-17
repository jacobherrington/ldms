require "json"
require "securerandom"
require "time"
require_relative "../db/sqlite"
require_relative "../db/vector_store"
require_relative "embedding_service"

module DevMemory
  module Services
    class MemoryService
      MEMORY_TYPES = %w[
        dev_preference
        project_convention
        architecture_decision
        bug_fix_note
        successful_pattern
        session_summary
        anti_pattern
      ].freeze

      HIGH_CONFIDENCE_SECRET_PATTERNS = [
        /-----BEGIN [A-Z ]*PRIVATE KEY-----/m,
        /\bAKIA[0-9A-Z]{16}\b/,
        /\bASIA[0-9A-Z]{16}\b/,
        /\bghp_[A-Za-z0-9]{20,}\b/,
        /\bxox[pbars]-[A-Za-z0-9-]{10,}\b/,
        /\bsk_(live|test)_[A-Za-z0-9]{16,}\b/i
      ].freeze

      REDACTION_PATTERNS = [
        [/(-----BEGIN [A-Z ]*PRIVATE KEY-----.*?-----END [A-Z ]*PRIVATE KEY-----)/m, "[REDACTED_PRIVATE_KEY]"],
        [/\bAKIA[0-9A-Z]{16}\b/, "[REDACTED_AWS_KEY]"],
        [/\bASIA[0-9A-Z]{16}\b/, "[REDACTED_AWS_KEY]"],
        [/\bghp_[A-Za-z0-9]{20,}\b/, "[REDACTED_GITHUB_TOKEN]"],
        [/\bxox[pbars]-[A-Za-z0-9-]{10,}\b/, "[REDACTED_SLACK_TOKEN]"],
        [/\bsk_(live|test)_[A-Za-z0-9]{16,}\b/i, "[REDACTED_PROVIDER_KEY]"],
        [/(\b(?:api[_-]?key|access[_-]?token|refresh[_-]?token|client[_-]?secret|secret(?:_key)?|password|passwd|credential|authorization)\b\s*[:=]\s*)(["']?)[A-Za-z0-9_\-\.=+\/]{8,}\2/i, '\1[REDACTED_SECRET]']
      ].freeze

      QUALITY_ACTIONS = %w[upvote downvote mark_stale mark_active archive unarchive].freeze
      FEEDBACK_REASONS = %w[irrelevant stale missing_project_context helpful].freeze
      RANKING_PROFILES = {
        "balanced" => { similarity: 0.6, confidence: 0.25, relevance: 0.1, freshness: 0.05 },
        "conservative" => { similarity: 0.55, confidence: 0.3, relevance: 0.12, freshness: 0.03 },
        "exploratory" => { similarity: 0.5, confidence: 0.2, relevance: 0.15, freshness: 0.15 }
      }.freeze
      DEVELOPER_SEED_LIBRARY = {
        "dhh" => [
          { memory_type: "project_convention", content: "Favor simple, integrated app design over unnecessary service splits.", tags: %w[rails simplicity] },
          { memory_type: "successful_pattern", content: "Prefer convention-driven code paths before introducing custom abstractions.", tags: %w[convention rails] },
          { memory_type: "anti_pattern", content: "Avoid overengineering early architecture before real constraints appear.", tags: %w[architecture pragmatism] }
        ],
        "sandi metz" => [
          { memory_type: "project_convention", content: "Keep methods small and focused to preserve changeability.", tags: %w[ruby design] },
          { memory_type: "successful_pattern", content: "Optimize for low coupling and clear object responsibilities.", tags: %w[oop maintainability] },
          { memory_type: "anti_pattern", content: "Avoid forcing inheritance when composition communicates intent better.", tags: %w[oop composition] }
        ],
        "martin fowler" => [
          { memory_type: "successful_pattern", content: "Refactor in small safe steps with tests protecting behavior.", tags: %w[refactor testing] },
          { memory_type: "architecture_decision", content: "Use evolutionary architecture and defer irreversible decisions.", tags: %w[architecture incremental] },
          { memory_type: "anti_pattern", content: "Avoid big-bang rewrites when incremental migration is possible.", tags: %w[migration risk] }
        ],
        "kent beck" => [
          { memory_type: "successful_pattern", content: "Write focused tests for desired behavior before broad refactors.", tags: %w[tdd testing] },
          { memory_type: "project_convention", content: "Choose the simplest change that can possibly work.", tags: %w[simplicity agile] },
          { memory_type: "anti_pattern", content: "Avoid speculative code paths that are not justified by current needs.", tags: %w[yagni pragmatism] }
        ],
        "aaron patterson" => [
          { memory_type: "successful_pattern", content: "Use query hygiene and eager loading to prevent N+1 regressions.", tags: %w[rails performance] },
          { memory_type: "project_convention", content: "Measure first, then optimize the true bottleneck.", tags: %w[profiling performance] },
          { memory_type: "anti_pattern", content: "Avoid premature micro-optimization without runtime evidence.", tags: %w[performance evidence] }
        ],
        "obie fernandez" => [
          { memory_type: "project_convention", content: "Keep Rails apps pragmatic and prioritize delivery over ceremony.", tags: %w[rails delivery] },
          { memory_type: "successful_pattern", content: "Extract focused service objects when controller/model complexity grows.", tags: %w[service_objects rails] },
          { memory_type: "anti_pattern", content: "Avoid bloated controllers that coordinate too many responsibilities.", tags: %w[controllers design] }
        ]
      }.freeze

      def initialize(
        db: DevMemory::DB::SQLite.connection,
        vector_store: DevMemory::DB::VectorStore.new,
        embedding_service: EmbeddingService.new
      )
        @db = db
        @vector_store = vector_store
        @embedding_service = embedding_service
      end

      def save_memory(content:, memory_type:, scope:, project_id:, confidence: 0.8, tags: [], source: "cursor")
        validate_memory_type!(memory_type)
        raise ArgumentError, "Refusing to store likely secret material" if high_confidence_secret?(content)
        sanitized_content = redact_secrets(content.to_s)

        id = SecureRandom.uuid
        now = Time.now.utc.iso8601
        summary = summarize(sanitized_content)
        normalized_tags = normalize_tags(tags)

        @db.execute(
          <<~SQL,
            INSERT INTO memories (
              id, content, summary, memory_type, scope, project_id, source, confidence, tags,
              state, relevance_score, is_archived, created_at, updated_at
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
          SQL
          [
            id, sanitized_content, summary, memory_type, scope, project_id, source, confidence.to_f, normalized_tags.to_json,
            "active", 0.0, 0, now, now
          ]
        )

        vector_indexed = true
        begin
          embedding = @embedding_service.embed(sanitized_content)
          @vector_store.upsert(
            memory_id: id,
            embedding: embedding,
            project_id: project_id,
            memory_type: memory_type,
            scope: scope,
            confidence: confidence.to_f,
            tags: normalized_tags
          )
        rescue EmbeddingService::EmbeddingError
          # Keep writes available when local embeddings are offline.
          vector_indexed = false
        end

        {
          status: "ok",
          memory_id: id,
          vector_indexed: vector_indexed
        }
      end

      def search_memory(query:, project_id:, top_k: 8, memory_types: nil, ranking_profile: "balanced")
        query_text = query.to_s
        begin
          query_embedding = @embedding_service.embed(query_text)
          vector_hits = @vector_store.search(
            query_embedding: query_embedding,
            project_id: project_id,
            top_k: [top_k.to_i * 4, 20].max,
            memory_types: memory_types
          )
          return rank_vector_hits(vector_hits: vector_hits, top_k: top_k, ranking_profile: ranking_profile)
        rescue EmbeddingService::EmbeddingError
          # Keep retrieval available during local embedding outages.
        end

        lexical_search_memory(
          query: query_text,
          project_id: project_id,
          top_k: top_k,
          memory_types: memory_types
        )
      end

      def list_memories(project_id: nil, memory_type: nil, query: nil, limit: 100, include_archived: false)
        sql = +"SELECT rowid AS _rowid, * FROM memories WHERE 1=1"
        bind_values = []

        if project_id && !project_id.to_s.strip.empty?
          sql << " AND project_id = ?"
          bind_values << project_id
        end

        if memory_type && !memory_type.to_s.strip.empty?
          sql << " AND memory_type = ?"
          bind_values << memory_type
        end

        if query && !query.to_s.strip.empty?
          sql << " AND (content LIKE ? OR summary LIKE ? OR tags LIKE ?)"
          query_term = "%#{query.strip}%"
          bind_values.concat([query_term, query_term, query_term])
        end

        sql << " AND COALESCE(is_archived, 0) = 0" unless include_archived

        sql << " ORDER BY datetime(created_at) DESC LIMIT ?"
        bind_values << [limit.to_i, 1].max

        rows = @db.execute(sql, bind_values)
        rows.map do |row|
          {
            id: row["id"],
            rowid: row["_rowid"].to_i,
            content: row["content"],
            summary: row["summary"],
            memory_type: row["memory_type"],
            scope: row["scope"],
            state: row["state"] || "active",
            project_id: row["project_id"],
            confidence: row["confidence"].to_f,
            relevance_score: row["relevance_score"].to_f,
            is_archived: row["is_archived"].to_i == 1,
            tags: parse_json_array(row["tags"]),
            created_at: row["created_at"]
          }
        end
      end

      def update_memory_quality(memory_id:, action:, reason: nil)
        normalized_action = action.to_s
        raise ArgumentError, "Invalid quality action `#{action}`" unless QUALITY_ACTIONS.include?(normalized_action)

        case normalized_action
        when "upvote"
          adjust_relevance(memory_id, 0.2)
          record_feedback(memory_id: memory_id, feedback: "helpful", reason: reason || "helpful")
        when "downvote"
          adjust_relevance(memory_id, -0.2)
          record_feedback(memory_id: memory_id, feedback: "not_helpful", reason: reason || "irrelevant")
        when "mark_stale"
          update_memory_state(memory_id, "stale")
          record_feedback(memory_id: memory_id, feedback: "not_helpful", reason: reason || "stale")
        when "mark_active"
          update_memory_state(memory_id, "active")
        when "archive"
          update_archived(memory_id, true)
        when "unarchive"
          update_archived(memory_id, false)
        end

        { status: "ok", memory_id: memory_id, action: normalized_action }
      end

      def update_memory_metadata(memory_id:, summary: nil, tags: nil)
        updates = []
        args = []
        if summary
          updates << "summary = ?"
          args << summary.to_s.strip
        end
        if tags
          updates << "tags = ?"
          args << normalize_tags(tags).to_json
        end
        return { status: "noop", memory_id: memory_id } if updates.empty?

        updates << "updated_at = ?"
        args << Time.now.utc.iso8601
        args << memory_id

        @db.execute("UPDATE memories SET #{updates.join(', ')} WHERE id = ?", args)
        { status: "ok", memory_id: memory_id }
      end

      def record_retrieval_feedback(memory_id:, helpful:, reason: nil)
        feedback = helpful ? "helpful" : "not_helpful"
        normalized_reason = normalize_reason(reason, helpful: helpful)
        record_feedback(memory_id: memory_id, feedback: feedback, reason: normalized_reason)
        adjust_relevance(memory_id, helpful ? 0.1 : -0.1)
        { status: "ok", memory_id: memory_id, feedback: feedback, reason: normalized_reason }
      end

      def delete_memory(memory_id:, memory_rowid: nil)
        id = memory_id.to_s.strip
        rowid = normalize_rowid(memory_rowid)
        return { status: "invalid", deleted: false, memory_id: id, memory_rowid: rowid } if id.empty? && rowid.nil?

        canonical_id = resolve_memory_id(id: id, rowid: rowid)
        @db.execute("DELETE FROM vectors WHERE memory_id = ?", [canonical_id]) unless canonical_id.nil?

        if rowid
          @db.execute("DELETE FROM memories WHERE id = ? OR rowid = ?", [id, rowid])
        else
          @db.execute("DELETE FROM memories WHERE id = ?", [id])
        end
        deleted = @db.changes.positive?

        {
          status: deleted ? "ok" : "not_found",
          deleted: deleted,
          memory_id: id,
          memory_rowid: rowid
        }
      end

      def log_decision(project_id:, title:, decision:, rationale:)
        id = SecureRandom.uuid
        now = Time.now.utc.iso8601

        @db.execute(
          <<~SQL,
            INSERT INTO decisions (id, project_id, title, decision, rationale, created_at)
            VALUES (?, ?, ?, ?, ?, ?)
          SQL
          [id, project_id, title, decision, rationale, now]
        )

        save_memory(
          content: "#{title}\nDecision: #{decision}\nRationale: #{rationale}",
          memory_type: "architecture_decision",
          scope: "project",
          project_id: project_id,
          confidence: 0.9,
          tags: ["decision"]
        )

        { decision_id: id }
      end

      def list_decisions(project_id: nil, limit: 100)
        sql = +"SELECT * FROM decisions WHERE 1=1"
        bind_values = []

        if project_id && !project_id.to_s.strip.empty?
          sql << " AND project_id = ?"
          bind_values << project_id
        end

        sql << " ORDER BY datetime(created_at) DESC LIMIT ?"
        bind_values << [limit.to_i, 1].max

        @db.execute(sql, bind_values).map do |row|
          {
            id: row["id"],
            project_id: row["project_id"],
            title: row["title"],
            decision: row["decision"],
            rationale: row["rationale"],
            created_at: row["created_at"]
          }
        end
      end

      def seed_developer_memories(developers:, project_id:, scope: "global", confidence: 0.86)
        normalized_developers = Array(developers).map { |name| normalize_developer_name(name) }.reject(&:empty?).uniq
        created = []
        skipped_existing = []
        skipped_unknown = []

        normalized_developers.each do |developer_name|
          templates = DEVELOPER_SEED_LIBRARY[developer_name]
          if templates.nil?
            skipped_unknown << developer_name
            next
          end

          templates.each do |template|
            content = "#{display_developer_name(developer_name)}: #{template[:content]}"
            memory_type = template[:memory_type]
            next skipped_existing << content if memory_exists?(content: content, memory_type: memory_type, project_id: project_id)

            result = save_memory(
              content: content,
              memory_type: memory_type,
              scope: scope,
              project_id: project_id,
              confidence: confidence,
              tags: ["seed", "developer", developer_name.tr(" ", "_")] + Array(template[:tags]),
              source: "developer_seed_tool"
            )
            created << result[:memory_id]
          end
        end

        {
          status: "ok",
          seeded_count: created.length,
          skipped_existing_count: skipped_existing.length,
          skipped_unknown_count: skipped_unknown.length,
          developers_requested: normalized_developers,
          developers_seeded: normalized_developers - skipped_unknown,
          skipped_unknown_developers: skipped_unknown
        }
      end

      private

      def normalize_developer_name(name)
        name.to_s.downcase.strip.gsub(/\s+/, " ")
      end

      def display_developer_name(name)
        name.split(" ").map(&:capitalize).join(" ")
      end

      def memory_exists?(content:, memory_type:, project_id:)
        sql = <<~SQL
          SELECT id FROM memories
          WHERE content = ?
            AND memory_type = ?
            AND COALESCE(project_id, '') = COALESCE(?, '')
          LIMIT 1
        SQL
        row = @db.get_first_row(sql, [content, memory_type, project_id])
        !row.nil?
      end

      def fetch_memories(ids)
        return [] if ids.empty?

        placeholders = (["?"] * ids.length).join(", ")
        @db.execute("SELECT * FROM memories WHERE id IN (#{placeholders})", ids)
      end

      def summarize(content)
        single_line = content.to_s.strip.gsub(/\s+/, " ")
        return single_line if single_line.length <= 160

        "#{single_line[0, 157]}..."
      end

      def normalize_tags(tags)
        Array(tags).map(&:to_s).map(&:strip).reject(&:empty?).uniq
      end

      def validate_memory_type!(memory_type)
        return if MEMORY_TYPES.include?(memory_type)

        raise ArgumentError, "Invalid memory_type `#{memory_type}`"
      end

      def high_confidence_secret?(content)
        text = content.to_s
        HIGH_CONFIDENCE_SECRET_PATTERNS.any? { |pattern| text.match?(pattern) }
      end

      def redact_secrets(content)
        REDACTION_PATTERNS.reduce(content.to_s) do |redacted, (pattern, replacement)|
          redacted.gsub(pattern, replacement)
        end
      end

      def parse_json_array(value)
        return [] if value.nil? || value.empty?

        parsed = JSON.parse(value)
        parsed.is_a?(Array) ? parsed : []
      rescue JSON::ParserError
        []
      end

      def archived?(memory_row)
        memory_row["is_archived"].to_i == 1 || memory_row["state"] == "archived"
      end

      def ranking_weights(profile_name)
        profile = profile_name.to_s.strip
        return RANKING_PROFILES["balanced"] if profile.empty?

        RANKING_PROFILES.fetch(profile, RANKING_PROFILES["balanced"])
      end

      def freshness(created_at)
        timestamp = Time.parse(created_at.to_s)
        age_hours = [(Time.now.utc - timestamp) / 3600.0, 0].max
        value = 1.0 - [age_hours / 72.0, 1.0].min
        value.round(4)
      rescue ArgumentError
        0.5
      end

      def normalized_relevance(value)
        [[(value.to_f + 1.0) / 2.0, 0.0].max, 1.0].min
      end

      def ranking_explanation(similarity:, confidence:, relevance_score:, freshness_score:, weights:)
        {
          profile: RANKING_PROFILES.find { |_name, w| w == weights }&.first || "balanced",
          factors: {
            similarity: similarity.round(4),
            confidence: confidence.round(4),
            relevance: normalized_relevance(relevance_score).round(4),
            freshness: freshness_score.round(4)
          },
          weights: weights
        }
      end

      def rank_vector_hits(vector_hits:, top_k:, ranking_profile:)
        rows = fetch_memories(vector_hits.map { |hit| hit[:memory_id] })
        by_id = rows.each_with_object({}) { |row, out| out[row["id"]] = row }
        weights = ranking_weights(ranking_profile)

        ranked = vector_hits.filter_map do |hit|
          memory = by_id[hit[:memory_id]]
          next unless memory
          next if archived?(memory)

          memory_result(
            memory: memory,
            similarity: hit[:similarity],
            weights: weights,
            ranking_explanation_payload: ranking_explanation(
              similarity: hit[:similarity],
              confidence: memory["confidence"].to_f,
              relevance_score: memory["relevance_score"].to_f,
              freshness_score: freshness(memory["created_at"]),
              weights: weights
            )
          )
        end

        ranked.sort_by { |row| -row[:combined_score] }.first(top_k.to_i)
      end

      def lexical_search_memory(query:, project_id:, top_k:, memory_types:)
        rows = fetch_lexical_candidates(
          query: query,
          project_id: project_id,
          top_k: top_k,
          memory_types: memory_types
        )
        tokens = tokenize_query(query)

        ranked = rows.filter_map do |memory|
          next if archived?(memory)

          similarity = lexical_similarity(memory: memory, tokens: tokens)
          next if similarity <= 0.0

          memory_result(
            memory: memory,
            similarity: similarity,
            weights: nil,
            ranking_explanation_payload: {
              profile: "lexical_fallback",
              factors: {
                lexical_similarity: similarity.round(4),
                confidence: memory["confidence"].to_f.round(4),
                relevance: normalized_relevance(memory["relevance_score"]).round(4),
                freshness: freshness(memory["created_at"]).round(4)
              },
              weights: nil
            }
          )
        end

        ranked.sort_by { |row| -row[:combined_score] }.first(top_k.to_i)
      end

      def fetch_lexical_candidates(query:, project_id:, top_k:, memory_types:)
        sql = +"SELECT * FROM memories WHERE COALESCE(is_archived, 0) = 0"
        bind_values = []

        if project_id && !project_id.to_s.strip.empty?
          sql << " AND project_id = ?"
          bind_values << project_id
        end

        if memory_types && !memory_types.empty?
          placeholders = (["?"] * memory_types.length).join(", ")
          sql << " AND memory_type IN (#{placeholders})"
          bind_values.concat(memory_types)
        end

        tokens = tokenize_query(query)
        token_conditions = tokens.map { "(content LIKE ? OR summary LIKE ? OR tags LIKE ?)" }
        if token_conditions.empty?
          sql << " AND (content LIKE ? OR summary LIKE ? OR tags LIKE ?)"
          like_query = "%#{query.to_s.strip}%"
          bind_values.concat([like_query, like_query, like_query])
        else
          sql << " AND (#{token_conditions.join(' OR ')})"
          tokens.each do |token|
            like_token = "%#{token}%"
            bind_values.concat([like_token, like_token, like_token])
          end
        end

        sql << " ORDER BY datetime(updated_at) DESC, datetime(created_at) DESC LIMIT ?"
        bind_values << [top_k.to_i * 6, 50].max

        @db.execute(sql, bind_values)
      end

      def tokenize_query(query)
        query.to_s.downcase.scan(/[a-z0-9_]+/).uniq.first(12)
      end

      def lexical_similarity(memory:, tokens:)
        return 0.0 if tokens.empty?

        searchable = [
          memory["content"].to_s.downcase,
          memory["summary"].to_s.downcase,
          memory["tags"].to_s.downcase
        ].join(" ")
        matches = tokens.count { |token| searchable.include?(token) }
        (matches.to_f / tokens.length).round(4)
      end

      def memory_result(memory:, similarity:, weights:, ranking_explanation_payload:)
        confidence = memory["confidence"].to_f
        relevance_score = memory["relevance_score"].to_f
        freshness_score = freshness(memory["created_at"])
        combined_score = if weights
                           (
                             (similarity * weights[:similarity]) +
                             (confidence * weights[:confidence]) +
                             (normalized_relevance(relevance_score) * weights[:relevance]) +
                             (freshness_score * weights[:freshness])
                           )
                         else
                           (
                             (similarity * 0.6) +
                             (confidence * 0.25) +
                             (normalized_relevance(relevance_score) * 0.1) +
                             (freshness_score * 0.05)
                           )
                         end
        combined_score -= 0.1 if memory["state"] == "stale"

        {
          id: memory["id"],
          content: memory["content"],
          summary: memory["summary"],
          memory_type: memory["memory_type"],
          scope: memory["scope"],
          project_id: memory["project_id"],
          confidence: confidence,
          similarity: similarity,
          combined_score: combined_score,
          state: memory["state"],
          relevance_score: relevance_score,
          ranking_explanation: ranking_explanation_payload,
          tags: parse_json_array(memory["tags"]),
          created_at: memory["created_at"]
        }
      end

      def adjust_relevance(memory_id, delta)
        row = @db.get_first_row("SELECT relevance_score FROM memories WHERE id = ?", [memory_id])
        current = row ? row["relevance_score"].to_f : 0.0
        next_score = [[current + delta, -1.0].max, 1.0].min
        @db.execute(
          "UPDATE memories SET relevance_score = ?, updated_at = ? WHERE id = ?",
          [next_score, Time.now.utc.iso8601, memory_id]
        )
      end

      def update_memory_state(memory_id, state)
        @db.execute(
          "UPDATE memories SET state = ?, updated_at = ? WHERE id = ?",
          [state, Time.now.utc.iso8601, memory_id]
        )
      end

      def update_archived(memory_id, archived)
        state = archived ? "archived" : "active"
        @db.execute(
          "UPDATE memories SET is_archived = ?, state = ?, updated_at = ? WHERE id = ?",
          [archived ? 1 : 0, state, Time.now.utc.iso8601, memory_id]
        )
      end

      def record_feedback(memory_id:, feedback:, reason:)
        @db.execute(
          <<~SQL,
            INSERT INTO memory_feedback (id, memory_id, feedback, reason, created_at)
            VALUES (?, ?, ?, ?, ?)
          SQL
          [SecureRandom.uuid, memory_id, feedback, reason, Time.now.utc.iso8601]
        )
      end

      def normalize_reason(reason, helpful:)
        text = reason.to_s.strip
        return helpful ? "helpful" : "irrelevant" if text.empty?
        return text if FEEDBACK_REASONS.include?(text)

        helpful ? "helpful" : "irrelevant"
      end

      def normalize_rowid(value)
        text = value.to_s.strip
        return nil if text.empty?

        parsed = Integer(text, 10)
        parsed.positive? ? parsed : nil
      rescue ArgumentError
        nil
      end

      def resolve_memory_id(id:, rowid:)
        return id unless id.empty?
        return nil if rowid.nil?

        row = @db.get_first_row("SELECT id FROM memories WHERE rowid = ?", [rowid])
        row && row["id"].to_s
      end
    end
  end
end
