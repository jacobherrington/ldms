require "securerandom"
require_relative "../test_helper"
require_relative "../../app/db/sqlite"
require_relative "../../app/db/vector_store"
require_relative "../../app/services/bootstrap_service"
require_relative "../../app/services/memory_service"

class FakeBootstrapEmbeddingService
  def embed(_text)
    [0.2, 0.3, 0.4]
  end
end

class BootstrapServiceTest < Minitest::Test
  def setup
    DevMemory::DB::SQLite.init_schema!
    db = DevMemory::DB::SQLite.connection
    memory_service = DevMemory::Services::MemoryService.new(
      db: db,
      vector_store: DevMemory::DB::VectorStore.new(db: db),
      embedding_service: FakeBootstrapEmbeddingService.new
    )

    @project_id = "bootstrap-test-#{SecureRandom.hex(4)}"
    @service = DevMemory::Services::BootstrapService.new(
      memory_service: memory_service,
      db: db,
      project_root: File.expand_path("../..", __dir__),
      project_id: @project_id
    )
  end

  def test_run_seeds_starter_memories
    result = @service.run

    assert_equal "ok", result[:status]
    assert result[:created_count] > 0
    assert_equal result[:created_count], result[:created_memory_ids].length
  end

  def test_run_is_idempotent_for_same_project
    first = @service.run
    second = @service.run

    assert first[:created_count] > 0
    assert_equal 0, second[:created_count]
    assert second[:skipped_count] >= first[:created_count]
  end
end
