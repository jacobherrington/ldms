require_relative "../test_helper"
require_relative "../../app/mcp/tools"

class FakeProfileServiceForTools
  def load_profile
    { "developer" => { "languages" => ["Ruby"] } }
  end

  def summary
    "summary"
  end
end

class FakeMemoryServiceForTools
  attr_reader :saved, :seeded

  def initialize
    @saved = []
    @seeded = []
  end

  def search_memory(query:, project_id:, top_k:, memory_types: nil)
    _ = [query, project_id, top_k, memory_types]
    []
  end

  def save_memory(**kwargs)
    @saved << kwargs
    { status: "ok", memory_id: "memory-1" }
  end

  def log_decision(**kwargs)
    _ = kwargs
    { decision_id: "decision-1" }
  end

  def seed_developer_memories(**kwargs)
    @seeded << kwargs
    {
      status: "ok",
      seeded_count: 3,
      skipped_existing_count: 0,
      skipped_unknown_count: 0,
      developers_requested: kwargs[:developers]
    }
  end
end

class FakeRetrievalServiceForTools
  attr_reader :last_args

  def get_context_packet(task:, project_id:, top_k:, memory_types: nil)
    @last_args = {
      task: task,
      project_id: project_id,
      top_k: top_k,
      memory_types: memory_types
    }
    { task: task, project: project_id, top_k: top_k, memory_types: memory_types }
  end

  def build_task_context(task:, project_id:, task_type:, top_k:)
    @last_args = {
      task: task,
      project_id: project_id,
      task_type: task_type,
      top_k: top_k
    }
    {
      task: task,
      project: project_id,
      task_type: task_type,
      working_context: {
        conventions: ["small service objects"],
        decisions: [],
        pitfalls: [],
        trace: { selected_memory_types: ["project_convention"] }
      }
    }
  end
end

class ToolsTest < Minitest::Test
  def setup
    @memory_service = FakeMemoryServiceForTools.new
    @retrieval_service = FakeRetrievalServiceForTools.new
    @tools = DevMemory::MCP::Tools.new(
      profile_service: FakeProfileServiceForTools.new,
      memory_service: @memory_service,
      retrieval_service: @retrieval_service,
      default_project_id: "default-project"
    )
  end

  def test_get_context_packet_uses_default_project_when_missing
    result = @tools.call("get_context_packet", { "task" => "build docs" })
    packet = result[:structuredContent][:context_packet]

    assert_equal "default-project", packet[:project]
  end

  def test_core_tool_contracts_are_present
    names = @tools.list.map { |tool| tool[:name] }
    assert_includes names, "get_dev_profile"
    assert_includes names, "search_memory"
    assert_includes names, "get_context_packet"
    assert_includes names, "begin_task_context"
    assert_includes names, "save_memory"
    assert_includes names, "seed_developer_memories"
    assert_includes names, "log_decision"
  end

  def test_call_response_includes_content_and_structured_payload
    result = @tools.call("get_dev_profile", {})
    assert result.key?(:content)
    assert result.key?(:structuredContent)
    assert_equal "text", result[:content].first[:type]
  end

  def test_save_memory_uses_default_project_when_missing
    @tools.call(
      "save_memory",
      {
        "content" => "use service objects",
        "memory_type" => "project_convention",
        "scope" => "project"
      }
    )

    assert_equal "default-project", @memory_service.saved.last[:project_id]
  end

  def test_unknown_tool_raises_argument_error
    assert_raises(ArgumentError) do
      @tools.call("unknown-tool", {})
    end
  end

  def test_missing_required_argument_raises_key_error
    assert_raises(KeyError) do
      @tools.call("search_memory", {})
    end
  end

  def test_get_context_packet_passes_memory_types_when_provided
    @tools.call(
      "get_context_packet",
      {
        "task" => "improve auth flow",
        "memory_types" => ["project_convention"]
      }
    )

    assert_equal ["project_convention"], @retrieval_service.last_args[:memory_types]
  end

  def test_begin_task_context_uses_default_project_when_missing
    result = @tools.call("begin_task_context", { "task" => "implement auth" })
    payload = result[:structuredContent][:task_context]

    assert_equal "default-project", payload[:project]
    assert_equal "auto", @retrieval_service.last_args[:task_type]
  end

  def test_begin_task_context_returns_working_context_keys
    result = @tools.call(
      "begin_task_context",
      {
        "task" => "fix flaky test",
        "task_type" => "test"
      }
    )
    context = result[:structuredContent][:task_context][:working_context]

    assert context.key?(:conventions)
    assert context.key?(:decisions)
    assert context.key?(:pitfalls)
    assert context.key?(:trace)
  end

  def test_seed_developer_memories_uses_defaults_and_project_resolution
    result = @tools.call(
      "seed_developer_memories",
      {
        "developers" => ["sandi metz", "kent beck"]
      }
    )

    assert_equal "ok", result[:structuredContent][:status]
    assert_equal "default-project", @memory_service.seeded.last[:project_id]
    assert_equal "global", @memory_service.seeded.last[:scope]
    assert_equal 0.86, @memory_service.seeded.last[:confidence]
  end
end
