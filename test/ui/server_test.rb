require_relative "../test_helper"
require_relative "../../app/ui/server"
require "json"

class UiServerTest < Minitest::Test
  def setup
    @server = DevMemory::UI::Server.new(port: 45_679, bind: "127.0.0.1")
  end

  def test_monitor_endpoint_returns_expected_shape
    req = fake_request(project_id: "default-project")
    res = fake_response

    @server.send(:render_monitor, req, res)
    payload = JSON.parse(res.body)

    assert payload.key?("memory_count")
    assert payload.key?("decision_count")
    assert payload.key?("memory_type_counts")
    assert payload.key?("updated_at")
  end

  def test_profile_endpoint_returns_profile_and_summary
    res = fake_response

    @server.send(:render_profile, res)
    payload = JSON.parse(res.body)

    assert payload.key?("profile")
    assert payload.key?("profile_summary")
  end

  def test_context_preview_requires_task
    req = fake_request(project_id: "alpha")
    res = fake_response

    error = assert_raises(ArgumentError) { @server.send(:render_context_preview, req, res) }
    assert_includes error.message, "task is required"
  end

  def test_value_or_nil_normalizes_blank_values
    assert_nil @server.send(:value_or_nil, "")
    assert_equal "alpha", @server.send(:value_or_nil, " alpha ")
  end

  private

  def fake_request(query = {})
    Struct.new(:query).new(query.transform_keys(&:to_s))
  end

  def fake_response
    Class.new do
      attr_accessor :status, :body

      def initialize
        @headers = {}
        @status = 200
        @body = ""
      end

      def []=(key, value)
        @headers[key] = value
      end
    end.new
  end
end
