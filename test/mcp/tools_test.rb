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
  attr_reader :saved

  def initialize
    @saved = []
  end

  def search_memory(query:, project_id:, top_k:, memory_types: nil, ranking_profile: "balanced")
    _ = [query, project_id, top_k, memory_types, ranking_profile]
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
end

class FakeRetrievalServiceForTools
  attr_reader :last_args

  def get_context_packet(task:, project_id:, top_k:, ranking_profile: "balanced", memory_types: nil)
    @last_args = {
      task: task,
      project_id: project_id,
      top_k: top_k,
      ranking_profile: ranking_profile,
      memory_types: memory_types
    }
    { task: task, project: project_id, top_k: top_k, ranking_profile: ranking_profile, memory_types: memory_types }
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
    assert_equal "balanced", @retrieval_service.last_args[:ranking_profile]
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
end
