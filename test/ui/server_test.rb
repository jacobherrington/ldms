require_relative "../test_helper"
require_relative "../../app/ui/server"
require "json"
require "tmpdir"
require "fileutils"

class ServerTestDouble < DevMemory::UI::Server
  def initialize
    super(port: 45_679, bind: "127.0.0.1")
  end

  def set_checks(docker:, docker_compose:, ollama:, ollama_api:, model:, mcp_ok:)
    @docker = docker
    @docker_compose = docker_compose
    @ollama = ollama
    @ollama_api = ollama_api
    @model = model
    @mcp_ok = mcp_ok
  end

  private

  def command_available?(name)
    return @docker if name == "docker"
    return @ollama if name == "ollama"

    false
  end

  def docker_compose_available?
    @docker_compose
  end

  def ollama_health
    [@ollama_api, @model]
  end

  def mcp_initialize_ok?
    { ok: @mcp_ok, output: "stub" }
  end
end

class UiServerTest < Minitest::Test
  def test_onboarding_status_all_passed
    server = ServerTestDouble.new
    server.set_checks(docker: true, docker_compose: true, ollama: true, ollama_api: true, model: true, mcp_ok: true)

    status = server.send(:onboarding_status, project_id: "default-project")

    assert_equal true, status[:all_passed]
    assert_equal 4, status[:checks].length
    assert status[:state].key?("steps")
    assert status[:progress].key?(:first_memory_saved)
  end

  def test_onboarding_status_detects_missing_dependency
    server = ServerTestDouble.new
    server.set_checks(docker: false, docker_compose: false, ollama: true, ollama_api: true, model: false, mcp_ok: false)

    status = server.send(:onboarding_status, project_id: "default-project")

    assert_equal false, status[:all_passed]
    missing = status[:checks].select { |check| !check[:ok] }
    assert missing.length >= 2
  end

  def test_update_onboarding_step_persists_state
    server = ServerTestDouble.new
    req = fake_request(step: "env_checks", completed: "true")
    res = fake_response

    server.send(:update_onboarding_step, req, res)
    payload = JSON.parse(res.body)

    assert_equal "ok", payload["status"]
    assert_equal true, payload.fetch("state").fetch("steps").fetch("env_checks")
  end

  def test_update_profile_updates_profile_and_marks_step
    server = ServerTestDouble.new
    with_temp_profile(server) do
      req = fake_request(
        languages: "Ruby,TypeScript",
        frameworks: "Rails,Next.js",
        comments: "concise",
        prefer_small_functions: "true",
        prefer_explicit_types: "false"
      )
      res = fake_response

      server.send(:update_profile, req, res)
      payload = JSON.parse(res.body)

      assert_equal "ok", payload["status"]
      assert_equal "concise", payload.fetch("profile").fetch("style").fetch("comments")

      state = server.instance_variable_get(:@session_service).get_onboarding_state
      assert_equal true, state.fetch("steps").fetch("profile")
    end
  end

  def test_command_action_payload_success
    server = ServerTestDouble.new
    payload = server.send(:command_action_payload, "ruby", "-e", "puts 'ok'")

    assert_equal "ok", payload[:status]
    assert_includes payload[:output], "ok"
  end

  def test_command_action_payload_error
    server = ServerTestDouble.new
    payload = server.send(:command_action_payload, "ruby", "-e", "exit 1")

    assert_equal "error", payload[:status]
  end

  def test_run_action_sequence_stops_after_failure
    server = ServerTestDouble.new
    result = server.send(
      :run_action_sequence,
      [
        { id: "pass", command: ["ruby", "-e", "exit 0"] },
        { id: "fail", command: ["ruby", "-e", "exit 1"] },
        { id: "skip", command: ["ruby", "-e", "exit 0"] }
      ]
    )

    assert_equal "error", result[:status]
    assert_equal "ok", result[:steps][0][:status]
    assert_equal "error", result[:steps][1][:status]
    assert_equal "skipped", result[:steps][2][:status]
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

  def with_temp_profile(server)
    Dir.mktmpdir("ui-server-profile-test") do |dir|
      original = DevMemory::Services::ProfileService::PROFILE_PATH
      temp = File.join(dir, "developer_profile.json")
      FileUtils.cp(original, temp)
      profile_service = DevMemory::Services::ProfileService.new(profile_path: temp)
      server.instance_variable_set(:@profile_service, profile_service)
      yield
    end
  end
end
