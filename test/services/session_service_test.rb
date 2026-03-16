require "securerandom"
require_relative "../test_helper"
require_relative "../../app/db/sqlite"
require_relative "../../app/services/session_service"

class SessionServiceTest < Minitest::Test
  def setup
    DevMemory::DB::SQLite.init_schema!
    @db = DevMemory::DB::SQLite.connection
    @service = DevMemory::Services::SessionService.new(db: @db)
    @project_id = "session-test-#{SecureRandom.hex(4)}"
  end

  def test_start_record_end_and_monitor_snapshot
    session_id = @service.start_session(project_id: @project_id)
    @service.record_request(
      session_id: session_id,
      method: "tools/call",
      tool_name: "get_context_packet",
      project_id: @project_id,
      status: "ok",
      duration_ms: 12
    )
    @service.record_request(
      session_id: session_id,
      method: "tools/call",
      tool_name: "save_memory",
      project_id: @project_id,
      status: "error",
      duration_ms: 18
    )

    snapshot_before_end = @service.monitor_snapshot(project_id: @project_id, limit: 5)
    assert_equal 1, snapshot_before_end[:active_session_count]
    assert_equal 1, snapshot_before_end[:recent_session_count]
    assert_equal 1, snapshot_before_end[:request_ok_count]
    assert_equal 1, snapshot_before_end[:request_error_count]
    assert_equal 15.0, snapshot_before_end[:avg_request_duration_ms]
    assert_equal session_id, snapshot_before_end[:latest_session][:id]

    @service.end_session(session_id: session_id)
    snapshot_after_end = @service.monitor_snapshot(project_id: @project_id, limit: 5)
    assert_equal 0, snapshot_after_end[:active_session_count]
  end
end
