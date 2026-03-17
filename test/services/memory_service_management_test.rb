require "securerandom"
require_relative "../test_helper"
require_relative "../../app/db/sqlite"
require_relative "../../app/db/vector_store"
require_relative "../../app/services/memory_service"
require_relative "../../app/services/embedding_service"

class FakeEmbeddingService
  def embed(_text)
    [0.1, 0.2, 0.3]
  end
end

class FailingEmbeddingService
  def embed(_text)
    raise DevMemory::Services::EmbeddingService::ConnectionError, "offline"
  end
end

class MemoryServiceManagementTest < Minitest::Test
  def setup
    DevMemory::DB::SQLite.init_schema!
    @db = DevMemory::DB::SQLite.connection
    @service = DevMemory::Services::MemoryService.new(
      db: @db,
      vector_store: DevMemory::DB::VectorStore.new(db: @db),
      embedding_service: FakeEmbeddingService.new
    )
    @project_id = "test-project-#{SecureRandom.hex(4)}"
  end

  def test_list_and_delete_memory
    created = @service.save_memory(
      content: "Use repository pattern for gateway boundaries",
      memory_type: "project_convention",
      scope: "project",
      project_id: @project_id,
      confidence: 0.8,
      tags: ["architecture"]
    )

    memories = @service.list_memories(project_id: @project_id, limit: 10)
    ids = memories.map { |memory| memory[:id] }
    assert_includes ids, created[:memory_id]

    result = @service.delete_memory(memory_id: created[:memory_id])
    assert_equal true, result[:deleted]
    assert_equal "ok", result[:status]

    memories_after_delete = @service.list_memories(project_id: @project_id, limit: 10)
    ids_after_delete = memories_after_delete.map { |memory| memory[:id] }
    refute_includes ids_after_delete, created[:memory_id]
  end

  def test_delete_memory_returns_not_found_for_unknown_id
    result = @service.delete_memory(memory_id: SecureRandom.uuid)

    assert_equal false, result[:deleted]
    assert_equal "not_found", result[:status]
  end

  def test_delete_memory_returns_invalid_for_blank_id
    result = @service.delete_memory(memory_id: "  ")

    assert_equal false, result[:deleted]
    assert_equal "invalid", result[:status]
  end

  def test_delete_memory_can_fallback_to_rowid_when_id_is_stale
    created = @service.save_memory(
      content: "Delete by rowid fallback",
      memory_type: "project_convention",
      scope: "project",
      project_id: @project_id,
      confidence: 0.8
    )
    row = @service.list_memories(project_id: @project_id, limit: 10)
                  .find { |memory| memory[:id] == created[:memory_id] }

    result = @service.delete_memory(memory_id: "stale-id", memory_rowid: row[:rowid])

    assert_equal true, result[:deleted]
    assert_equal "ok", result[:status]
    remaining = @service.list_memories(project_id: @project_id, limit: 10)
    refute_includes remaining.map { |memory| memory[:id] }, created[:memory_id]
  end

  def test_redacts_assignment_style_secret_before_persisting
    created = @service.save_memory(
      content: 'Set API_KEY="abcdef1234567890" for local testing only',
      memory_type: "project_convention",
      scope: "project",
      project_id: @project_id,
      confidence: 0.8
    )

    memory = @service.list_memories(project_id: @project_id, limit: 10)
                     .find { |row| row[:id] == created[:memory_id] }

    refute_nil memory
    assert_includes memory[:content], "[REDACTED_SECRET]"
    refute_includes memory[:content], "abcdef1234567890"
  end

  def test_rejects_high_confidence_secret_material
    assert_raises(ArgumentError) do
      @service.save_memory(
        content: "-----BEGIN PRIVATE KEY-----\nabc\n-----END PRIVATE KEY-----",
        memory_type: "project_convention",
        scope: "project",
        project_id: @project_id,
        confidence: 0.8
      )
    end
  end

  def test_quality_actions_update_state_and_relevance
    created = @service.save_memory(
      content: "Keep retries idempotent",
      memory_type: "successful_pattern",
      scope: "project",
      project_id: @project_id,
      confidence: 0.8
    )
    memory_id = created[:memory_id]

    @service.update_memory_quality(memory_id: memory_id, action: "upvote")
    @service.update_memory_quality(memory_id: memory_id, action: "mark_stale")
    @service.update_memory_quality(memory_id: memory_id, action: "archive")

    memory = @service.list_memories(project_id: @project_id, include_archived: true).find { |m| m[:id] == memory_id }
    assert_equal "archived", memory[:state]
    assert memory[:relevance_score] > 0
    assert_equal true, memory[:is_archived]
  end

  def test_feedback_changes_relevance_and_stays_searchable_when_not_archived
    created = @service.save_memory(
      content: "Prefer focused service objects for side effects",
      memory_type: "project_convention",
      scope: "project",
      project_id: @project_id,
      confidence: 0.7
    )
    memory_id = created[:memory_id]

    @service.record_retrieval_feedback(memory_id: memory_id, helpful: false, reason: "irrelevant")
    @service.record_retrieval_feedback(memory_id: memory_id, helpful: true, reason: "helpful")

    memory = @service.list_memories(project_id: @project_id).find { |m| m[:id] == memory_id }
    refute_nil memory
    assert_in_delta 0.0, memory[:relevance_score], 0.11
  end

  def test_search_memory_uses_lexical_fallback_when_embeddings_fail
    @service.save_memory(
      content: "Auth tokens should rotate with short expiry windows",
      memory_type: "project_convention",
      scope: "project",
      project_id: @project_id,
      confidence: 0.8,
      tags: ["auth"]
    )

    fallback_service = DevMemory::Services::MemoryService.new(
      db: @db,
      vector_store: DevMemory::DB::VectorStore.new(db: @db),
      embedding_service: FailingEmbeddingService.new
    )

    results = fallback_service.search_memory(
      query: "auth token expiry",
      project_id: @project_id,
      top_k: 5,
      memory_types: ["project_convention"]
    )

    refute_empty results
    assert_equal "lexical_fallback", results.first[:ranking_explanation][:profile]
    assert_equal "project_convention", results.first[:memory_type]
  end

  def test_save_memory_succeeds_when_embeddings_are_offline
    degraded_service = DevMemory::Services::MemoryService.new(
      db: @db,
      vector_store: DevMemory::DB::VectorStore.new(db: @db),
      embedding_service: FailingEmbeddingService.new
    )

    result = degraded_service.save_memory(
      content: "Retries should use capped backoff",
      memory_type: "project_convention",
      scope: "project",
      project_id: @project_id,
      confidence: 0.8
    )

    assert_equal "ok", result[:status]
    assert_equal false, result[:vector_indexed]
    memory = degraded_service.list_memories(project_id: @project_id).find { |row| row[:id] == result[:memory_id] }
    refute_nil memory
  end

  def test_seed_developer_memories_creates_records_and_skips_duplicates
    seeded = @service.seed_developer_memories(
      developers: ["Sandi Metz", "Unknown Dev"],
      project_id: @project_id
    )
    assert_equal 3, seeded[:seeded_count]
    assert_equal 1, seeded[:skipped_unknown_count]

    seeded_again = @service.seed_developer_memories(
      developers: ["Sandi Metz"],
      project_id: @project_id
    )
    assert_equal 0, seeded_again[:seeded_count]
    assert_equal 3, seeded_again[:skipped_existing_count]
  end
end
