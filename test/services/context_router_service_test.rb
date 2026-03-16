require "securerandom"
require_relative "../test_helper"
require_relative "../../app/db/sqlite"
require_relative "../../app/services/context_router_service"

class FakeMemoryForRouterTest
  def search_memory(query:, project_id:, top_k:, memory_types: nil, ranking_profile: "balanced")
    _ = [query, top_k, memory_types, ranking_profile]
    [{ id: "#{project_id || 'global'}-1", project_id: project_id, confidence: 0.8 }]
  end
end

class FakeRepoIndexForRouterTest
  def query_index(project_id:, query:, limit:)
    _ = [project_id, query, limit]
    [{ path: "app/services/foo.rb", symbols: ["FooService"] }]
  end

  def git_context(workspace_root:)
    _ = workspace_root
    { git_status_short: ["M app/services/foo.rb"], latest_commit: "abc123 test" }
  end
end

class ContextRouterServiceTest < Minitest::Test
  def setup
    DevMemory::DB::SQLite.init_schema!
    @db = DevMemory::DB::SQLite.connection
    @service = DevMemory::Services::ContextRouterService.new(
      memory_service: FakeMemoryForRouterTest.new,
      repo_index_service: FakeRepoIndexForRouterTest.new,
      db: @db
    )
    @project_id = "router-#{SecureRandom.hex(3)}"
  end

  def test_build_context_returns_trace_and_sources
    packet = @service.build_context(
      task: "refactor class behavior using recent commit context",
      project_id: @project_id,
      top_k: 4,
      ranking_profile: "balanced",
      workspace_root: Dir.pwd
    )

    assert packet[:context_trace][:selected_sources].include?("memory")
    assert packet[:context_trace][:selected_sources].include?("repo_index")
    assert packet[:context_trace][:selected_sources].include?("git")
    refute_empty packet[:repo_hints]
    assert_equal "abc123 test", packet[:git_context][:latest_commit]
  end
end
