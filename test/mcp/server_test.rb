require "json"
require "stringio"
require_relative "../test_helper"
require_relative "../../app/mcp/server"

class FakeToolsForServerTest
  def call(name, _arguments)
    raise "forced failure" if name == "explode"

    { content: [{ type: "text", text: "ok" }], structuredContent: { ok: true } }
  end

  def list
    []
  end
end

class FakeSessionServiceForServerTest
  attr_reader :started_sessions, :ended_sessions, :requests

  def initialize
    @started_sessions = []
    @ended_sessions = []
    @requests = []
  end

  def start_session(project_id:)
    id = "session-#{@started_sessions.length + 1}"
    @started_sessions << { id: id, project_id: project_id }
    id
  end

  def end_session(session_id:)
    @ended_sessions << session_id
  end

  def record_request(**kwargs)
    @requests << kwargs
  end

  def get_setting(_key, default:)
    default
  end
end

class ServerTest < Minitest::Test
  def test_records_ok_request_and_closes_session_at_eof
    input = StringIO.new(
      [
        { jsonrpc: "2.0", id: 1, method: "initialize", params: {} }.to_json,
        { jsonrpc: "2.0", id: 2, method: "tools/call", params: { name: "get_dev_profile", arguments: {} } }.to_json
      ].join("\n") + "\n"
    )
    output = StringIO.new
    error = StringIO.new
    session_service = FakeSessionServiceForServerTest.new

    server = DevMemory::MCP::Server.new(
      input: input,
      output: output,
      error: error,
      tools: FakeToolsForServerTest.new,
      session_service: session_service
    )

    server.start

    assert_equal 1, session_service.started_sessions.length
    assert_equal ["session-1"], session_service.ended_sessions
    assert_equal 1, session_service.requests.length
    assert_equal "ok", session_service.requests.first[:status]
    assert_nil session_service.requests.first[:tool_name]
  end

  def test_records_error_request_when_tool_call_fails
    input = StringIO.new(
      [
        { jsonrpc: "2.0", id: 1, method: "initialize", params: {} }.to_json,
        { jsonrpc: "2.0", id: 2, method: "tools/call", params: { name: "explode", arguments: {} } }.to_json
      ].join("\n") + "\n"
    )
    output = StringIO.new
    error = StringIO.new
    session_service = FakeSessionServiceForServerTest.new

    server = DevMemory::MCP::Server.new(
      input: input,
      output: output,
      error: error,
      tools: FakeToolsForServerTest.new,
      session_service: session_service
    )

    server.start

    assert_equal 1, session_service.requests.length
    assert_equal "error", session_service.requests.first[:status]

    responses = output.string.split("\n").map { |line| JSON.parse(line) }
    error_response = responses.find { |r| r["id"] == 2 }
    refute_nil error_response
    assert_equal(-32000, error_response.fetch("error").fetch("code"))
  end
end
