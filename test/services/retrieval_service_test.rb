require_relative "../test_helper"
require_relative "../../app/services/retrieval_service"

class FakeMemoryService
  def search_memory(query:, project_id:, top_k:, memory_types: nil, ranking_profile: "balanced")
    _ = [query, top_k, memory_types, ranking_profile]
    return [{ id: "project-1", project_id: "alpha", confidence: 0.9 }] if project_id == "alpha"

    [
      { id: "project-1", project_id: "alpha", confidence: 0.7 },
      { id: "global-1", project_id: "global", confidence: 0.8 }
    ]
  end
end

class FakeProfileService
  def summary
    "profile-summary"
  end
end

class RetrievalServiceTest < Minitest::Test
  def setup
    @service = DevMemory::Services::RetrievalService.new(
      memory_service: FakeMemoryService.new,
      profile_service: FakeProfileService.new
    )
  end

  def test_get_context_packet_merges_project_and_global_without_duplicate_ids
    packet = @service.get_context_packet(task: "auth flow", project_id: "alpha", top_k: 5)

    assert_equal "auth flow", packet[:task]
    assert_equal "alpha", packet[:project]
    assert_equal "profile-summary", packet[:developer_profile_summary]
    assert_equal %w[project-1 global-1], packet[:retrieved_memories].map { |row| row[:id] }
  end

  def test_debug_context_returns_shape
    payload = @service.debug_context(query: "auth flow", project_id: "alpha", top_k: 3)

    assert_equal "auth flow", payload[:query]
    assert_equal "alpha", payload[:project_id]
    assert_equal 3, payload[:top_k]
    assert payload[:results].is_a?(Array)
  end
end
