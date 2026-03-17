require_relative "../test_helper"
require_relative "../../app/services/memory_loop_service"

class FakeMemoryServiceForLoop
  attr_reader :saved_memories, :logged_decisions

  def initialize
    @saved_memories = []
    @logged_decisions = []
  end

  def save_memory(**kwargs)
    @saved_memories << kwargs
    { status: "ok", memory_id: "memory-#{@saved_memories.length}" }
  end

  def log_decision(**kwargs)
    @logged_decisions << kwargs
    { decision_id: "decision-#{@logged_decisions.length}" }
  end
end

class MemoryLoopServiceTest < Minitest::Test
  def setup
    @memory_service = FakeMemoryServiceForLoop.new
    @service = DevMemory::Services::MemoryLoopService.new(memory_service: @memory_service)
  end

  def test_process_task_review_saves_high_confidence_memory_candidates
    result = @service.process_task_review(
      task: "improve startup flow",
      project_id: "dev-memory",
      review_text: <<~TEXT
        Convention: Keep setup one command.
        Pattern: Add explicit smoke checks.
      TEXT
    )

    assert_equal "ok", result[:status]
    assert_equal 2, result[:saved_count]
    assert_equal 2, @memory_service.saved_memories.length
  end

  def test_process_task_review_routes_architecture_decision_to_log_decision
    result = @service.process_task_review(
      task: "stabilize retrieval pipeline",
      project_id: "dev-memory",
      review_text: "Decision: Keep retrieval memory-only for MVP."
    )

    assert_equal 1, result[:saved_decision_count]
    assert_equal 1, @memory_service.logged_decisions.length
    assert_equal 0, @memory_service.saved_memories.length
  end

  def test_process_task_review_suggests_low_confidence_or_temporary_notes
    result = @service.process_task_review(
      task: "cleanup tool output",
      project_id: "dev-memory",
      review_text: "Maybe temporary workaround for now",
      auto_save_threshold: 0.9
    )

    assert_equal 0, result[:saved_count]
    assert_equal 1, result[:suggestion_count]
    assert_empty @memory_service.saved_memories
  end
end
