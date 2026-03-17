require_relative "../test_helper"
require_relative "../../app/services/retrieval_service"

class FakeMemoryService
  def search_memory(query:, project_id:, top_k:, memory_types: nil)
    _ = [query, top_k]
    pool = if project_id == "alpha"
             [
               {
                 id: "project-convention-1",
                 project_id: "alpha",
                 memory_type: "project_convention",
                 summary: "Use service objects for side effects",
                 content: "Use service objects for side effects",
                 confidence: 0.9
               },
               {
                 id: "project-decision-1",
                 project_id: "alpha",
                 memory_type: "architecture_decision",
                 summary: "Keep a monolith-first architecture",
                 content: "Keep a monolith-first architecture",
                 confidence: 0.9
               },
               {
                 id: "project-antipattern-1",
                 project_id: "alpha",
                 memory_type: "anti_pattern",
                 summary: "Avoid fat controllers",
                 content: "Avoid fat controllers",
                 confidence: 0.8
               }
             ]
           else
             [
               {
                 id: "global-pattern-1",
                 project_id: "global",
                 memory_type: "successful_pattern",
                 summary: "Add focused regression tests",
                 content: "Add focused regression tests",
                 confidence: 0.8
               }
             ]
           end
    return pool if memory_types.nil? || memory_types.empty?

    pool.select { |row| memory_types.include?(row[:memory_type]) }
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
    assert_equal %w[project-convention-1 project-decision-1 project-antipattern-1 global-pattern-1],
                 packet[:retrieved_memories].map { |row| row[:id] }
  end

  def test_debug_context_returns_shape
    payload = @service.debug_context(query: "auth flow", project_id: "alpha", top_k: 3)

    assert_equal "auth flow", payload[:query]
    assert_equal "alpha", payload[:project_id]
    assert_equal 3, payload[:top_k]
    assert payload[:results].is_a?(Array)
  end

  def test_build_task_context_routes_feature_memories
    packet = @service.build_task_context(
      task: "implement account onboarding flow",
      project_id: "alpha",
      task_type: "feature",
      top_k: 8
    )

    assert_equal "feature", packet[:task_type]
    assert_includes packet[:working_context][:conventions], "Use service objects for side effects"
    assert_equal ["Keep a monolith-first architecture"], packet[:working_context][:decisions]
    assert_empty packet[:working_context][:pitfalls]
    assert_equal %w[project_convention architecture_decision successful_pattern],
                 packet[:working_context][:trace][:selected_memory_types]
  end

  def test_build_task_context_infers_bugfix_from_task_keywords
    packet = @service.build_task_context(
      task: "fix production auth regression",
      project_id: "alpha",
      top_k: 8
    )

    assert_equal "bugfix", packet[:task_type]
    assert_equal ["Avoid fat controllers"], packet[:working_context][:pitfalls]
    assert_equal "task_keywords", packet[:context_trace][:task_type_inference][:inferred_from]
  end
end
