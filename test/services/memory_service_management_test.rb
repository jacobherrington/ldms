require "securerandom"
require_relative "../test_helper"
require_relative "../../app/db/sqlite"
require_relative "../../app/db/vector_store"
require_relative "../../app/services/memory_service"

class FakeEmbeddingService
  def embed(_text)
    [0.1, 0.2, 0.3]
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

    memories_after_delete = @service.list_memories(project_id: @project_id, limit: 10)
    ids_after_delete = memories_after_delete.map { |memory| memory[:id] }
    refute_includes ids_after_delete, created[:memory_id]
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
end
