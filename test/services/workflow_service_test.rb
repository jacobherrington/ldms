require "securerandom"
require_relative "../test_helper"
require_relative "../../app/db/sqlite"
require_relative "../../app/services/workflow_service"

class FakeRetrievalForWorkflowTest
  def get_context_packet(task:, project_id:, top_k:, ranking_profile: "balanced", memory_types: nil)
    _ = [task, project_id, top_k, ranking_profile, memory_types]
    { retrieved_memories: [], context_trace: { selected_sources: ["memory"] } }
  end
end

class FakeRepoIndexForWorkflowTest
  def query_index(project_id:, query:, limit:)
    _ = [project_id, query, limit]
    [{ path: "app/services/workflow_service.rb", symbols: ["WorkflowService"] }]
  end
end

class WorkflowServiceTest < Minitest::Test
  def setup
    DevMemory::DB::SQLite.init_schema!
    @db = DevMemory::DB::SQLite.connection
    @service = DevMemory::Services::WorkflowService.new(
      db: @db,
      retrieval_service: FakeRetrievalForWorkflowTest.new,
      repo_index_service: FakeRepoIndexForWorkflowTest.new
    )
    @project_id = "workflow-#{SecureRandom.hex(3)}"
  end

  def test_run_creates_dry_run_record
    result = @service.run(
      workflow_type: "implement_feature",
      prompt: "Implement password reset flow",
      project_id: @project_id,
      dry_run: true
    )

    assert_equal "dry_run", result[:status]
    runs = @service.list_runs(project_id: @project_id, limit: 5)
    refute_empty runs
    assert_equal "implement_feature", runs.first[:workflow_type]
  end
end
