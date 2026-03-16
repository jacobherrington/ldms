require_relative "../test_helper"
require_relative "../../app/services/retrieval_service"

class EvalFakeMemoryService
  def search_memory(query:, project_id:, top_k:, memory_types: nil, ranking_profile: "balanced")
    _ = [query, project_id, top_k, memory_types, ranking_profile]
    [
      { id: "m1", project_id: "demo", confidence: 0.9, combined_score: 0.9, summary: "Auth flow convention" },
      { id: "m2", project_id: "demo", confidence: 0.7, combined_score: 0.7, summary: "Retry pattern" }
    ]
  end
end

class EvalFakeProfileService
  def summary
    "profile"
  end
end

class RetrievalEvalTest < Minitest::Test
  def test_retrieval_quality_baseline
    service = DevMemory::Services::RetrievalService.new(
      memory_service: EvalFakeMemoryService.new,
      profile_service: EvalFakeProfileService.new,
      context_router: nil
    )
    packet = service.get_context_packet(task: "auth flow", project_id: "demo", top_k: 2)
    assert packet[:retrieved_memories].length >= 1
    assert packet[:retrieved_memories].first[:summary].downcase.include?("auth")
  end
end
