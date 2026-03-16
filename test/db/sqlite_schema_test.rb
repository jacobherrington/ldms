require_relative "../test_helper"
require_relative "../../app/db/sqlite"

class SqliteSchemaTest < Minitest::Test
  def setup
    DevMemory::DB::SQLite.init_schema!
  end

  def test_required_tables_exist
    db = DevMemory::DB::SQLite.connection
    rows = db.execute("SELECT name FROM sqlite_master WHERE type='table'")
    names = rows.map { |r| r["name"] }

    assert_includes names, "memories"
    assert_includes names, "decisions"
    assert_includes names, "sessions"
    assert_includes names, "mcp_requests"
    assert_includes names, "memory_feedback"
    assert_includes names, "app_settings"
    assert_includes names, "repo_index_entries"
    assert_includes names, "workflow_runs"
    assert_includes names, "vectors"
  end
end
