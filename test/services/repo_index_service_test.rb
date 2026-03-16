require "fileutils"
require "securerandom"
require_relative "../test_helper"
require_relative "../../app/db/sqlite"
require_relative "../../app/services/repo_index_service"

class RepoIndexServiceTest < Minitest::Test
  def setup
    DevMemory::DB::SQLite.init_schema!
    @db = DevMemory::DB::SQLite.connection
    @service = DevMemory::Services::RepoIndexService.new(db: @db)
    @project_id = "repo-index-#{SecureRandom.hex(3)}"
    @workspace = File.join(Dir.pwd, "tmp", "repo-index-#{SecureRandom.hex(3)}")
    FileUtils.mkdir_p(@workspace)
    File.write(File.join(@workspace, "sample.rb"), "class Alpha\n  def run!\n  end\nend\n")
    File.write(File.join(@workspace, "notes.md"), "# Alpha\n")
  end

  def teardown
    FileUtils.rm_rf(@workspace)
  end

  def test_index_workspace_and_query
    result = @service.index_workspace(project_id: @project_id, workspace_root: @workspace, max_files: 20)
    assert_equal "ok", result[:status]
    assert result[:indexed_files] >= 2

    hits = @service.query_index(project_id: @project_id, query: "Alpha", limit: 5)
    refute_empty hits
    assert_includes hits.first[:symbols], "Alpha"
  end
end
