require_relative "../test_helper"
require_relative "../../app/db/sqlite"
require_relative "../../app/services/workflow_service"

class EvalWorkflowRetrievalStub
  def get_context_packet(task:, project_id:, top_k:, ranking_profile: "balanced", memory_types: nil)
    _ = [task, project_id, top_k, ranking_profile, memory_types]
    { retrieved_memories: [], context_trace: { selected_sources: ["memory"] } }
  end
end

class EvalWorkflowRepoStub
  def query_index(project_id:, query:, limit:)
    _ = [project_id, query, limit]
    []
  end
end

class WorkflowEvalTest < Minitest::Test
  def setup
    DevMemory::DB::SQLite.init_schema!
    @service = DevMemory::Services::WorkflowService.new(
      retrieval_service: EvalWorkflowRetrievalStub.new,
      repo_index_service: EvalWorkflowRepoStub.new
    )
  end

  def test_workflow_success_baseline
    result = @service.run(
      workflow_type: "fix_failing_test",
      prompt: "Fix flaky test around retry logic",
      project_id: "eval-project",
      dry_run: true
    )
    assert_equal "dry_run", result[:status]
    assert result[:guardrail][:allowed]
  end
end
