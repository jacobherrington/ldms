require "securerandom"
require_relative "../test_helper"
require_relative "../../app/db/sqlite"
require_relative "../../app/services/memory_service"
require_relative "../../app/services/kpi_service"

class KpiFakeEmbeddingService
  def embed(_text)
    [0.1, 0.2, 0.3]
  end
end

class KpiServiceTest < Minitest::Test
  def setup
    DevMemory::DB::SQLite.init_schema!
    @db = DevMemory::DB::SQLite.connection
    @memory_service = DevMemory::Services::MemoryService.new(
      db: @db,
      embedding_service: KpiFakeEmbeddingService.new
    )
    @kpi = DevMemory::Services::KpiService.new(db: @db)
    @project_id = "kpi-#{SecureRandom.hex(3)}"
  end

  def test_weekly_snapshot_contains_top_failure_modes
    created = @memory_service.save_memory(
      content: "Prefer service object retries",
      memory_type: "project_convention",
      scope: "project",
      project_id: @project_id
    )
    @memory_service.record_retrieval_feedback(memory_id: created[:memory_id], helpful: false, reason: "irrelevant")

    snapshot = @kpi.weekly_snapshot(project_id: @project_id)
    assert_equal 1, snapshot[:dissatisfaction_count]
    assert snapshot[:top_failure_modes].any?
  end
end
