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
    [{ name: "get_dev_profile", inputSchema: { type: "object" } }]
  end
end

class ServerTest < Minitest::Test
  def test_initialize_response_contains_server_metadata_and_instructions
    input = StringIO.new(
      { jsonrpc: "2.0", id: 1, method: "initialize", params: {} }.to_json + "\n"
    )
    output = StringIO.new
    error = StringIO.new

    server = DevMemory::MCP::Server.new(
      input: input,
      output: output,
      error: error,
      tools: FakeToolsForServerTest.new
    )

    server.start

    response = JSON.parse(output.string.split("\n").first)
    assert_equal "2.0", response["jsonrpc"]
    result = response.fetch("result")
    assert_equal "dev-memory", result.fetch("serverInfo").fetch("name")
    assert result.fetch("instructions").include?("Default project_id is")
  end

  def test_handles_initialize_and_tool_call
    input = StringIO.new(
      [
        { jsonrpc: "2.0", id: 1, method: "initialize", params: {} }.to_json,
        { jsonrpc: "2.0", id: 2, method: "tools/call", params: { name: "get_dev_profile", arguments: {} } }.to_json
      ].join("\n") + "\n"
    )
    output = StringIO.new
    error = StringIO.new

    server = DevMemory::MCP::Server.new(
      input: input,
      output: output,
      error: error,
      tools: FakeToolsForServerTest.new
    )

    server.start

    responses = output.string.split("\n").map { |line| JSON.parse(line) }
    tool_response = responses.find { |r| r["id"] == 2 }
    refute_nil tool_response
    assert_equal true, tool_response.fetch("result").fetch("structuredContent").fetch("ok")
  end

  def test_tools_list_round_trip_uses_tools_catalog
    input = StringIO.new(
      [
        { jsonrpc: "2.0", id: 1, method: "initialize", params: {} }.to_json,
        { jsonrpc: "2.0", id: 2, method: "tools/list", params: {} }.to_json
      ].join("\n") + "\n"
    )
    output = StringIO.new
    error = StringIO.new

    server = DevMemory::MCP::Server.new(
      input: input,
      output: output,
      error: error,
      tools: FakeToolsForServerTest.new
    )

    server.start

    responses = output.string.split("\n").map { |line| JSON.parse(line) }
    list_response = responses.find { |payload| payload["id"] == 2 }
    refute_nil list_response
    tool_name = list_response.fetch("result").fetch("tools").first.fetch("name")
    assert_equal "get_dev_profile", tool_name
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

    server = DevMemory::MCP::Server.new(
      input: input,
      output: output,
      error: error,
      tools: FakeToolsForServerTest.new
    )

    server.start

    responses = output.string.split("\n").map { |line| JSON.parse(line) }
    error_response = responses.find { |r| r["id"] == 2 }
    refute_nil error_response
    assert_equal(-32000, error_response.fetch("error").fetch("code"))
  end
end
