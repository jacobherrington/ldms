#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "dotenv/load"
require_relative "../db/sqlite"
require_relative "../services/session_service"
require_relative "tools"

module DevMemory
  module MCP
    class Server
      def initialize(
        input: $stdin,
        output: $stdout,
        error: $stderr,
        tools: nil,
        session_service: nil
      )
        @input = input
        @output = output
        @error = error
        DevMemory::DB::SQLite.init_schema!
        @workspace_root = Dir.pwd
        @default_project_id = ENV["LDMS_PROJECT_ID"] || File.basename(@workspace_root)
        @tools = tools || Tools.new(default_project_id: @default_project_id)
        @session_service = session_service || DevMemory::Services::SessionService.new
        @session_id = nil
        @telemetry_enabled = ENV.fetch("LDMS_MONITOR_TELEMETRY", "true") != "false"
      end

      def start
        @input.each_line do |line|
          request = JSON.parse(line, symbolize_names: true)
          handle_request(request)
        rescue JSON::ParserError => e
          @error.puts("Invalid JSON request: #{e.message}")
        rescue StandardError => e
          respond_error(nil, -32000, e.message)
        end
      ensure
        ensure_session_closed!
      end

      private

      def handle_request(request)
        method = request[:method]
        params = request[:params] || {}
        id = request[:id]

        case method
        when "initialize"
          reset_session!
          respond(id, {
                    protocolVersion: "2024-11-05",
                    serverInfo: {
                      name: "dev-memory",
                      version: "0.1.0"
                    },
                    capabilities: {
                      tools: {}
                    },
                    instructions: "Default project_id is #{@default_project_id} (workspace: #{@workspace_root})."
                  })
        when "notifications/initialized"
          # no-op notification
        when "tools/list"
          respond(id, { tools: @tools.list })
        when "tools/call"
          handle_tool_call(id: id, params: params)
        when "ping"
          respond(id, {})
        else
          respond_error(id, -32601, "Method not found: #{method}")
        end
      rescue KeyError => e
        respond_error(id, -32602, "Invalid params: #{e.message}")
      rescue StandardError => e
        respond_error(id, -32000, e.message)
      end

      def stringify_keys(hash)
        hash.each_with_object({}) { |(k, v), out| out[k.to_s] = v }
      end

      def handle_tool_call(id:, params:)
        start_time = nil
        name = params.fetch(:name)
        args = stringify_keys(params[:arguments] || {})
        start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

        result = @tools.call(name, args)
        elapsed_ms = elapsed_ms_since(start_time)
        safe_record_request(
          method: "tools/call",
          tool_name: name,
          project_id: resolve_project_id(args["project_id"]),
          status: "ok",
          duration_ms: elapsed_ms
        )
        respond(id, result)
      rescue StandardError => e
        safe_record_request(
          method: "tools/call",
          tool_name: params[:name],
          project_id: resolve_project_id((params[:arguments] || {})[:project_id]),
          status: "error",
          duration_ms: elapsed_ms_since(start_time)
        )
        raise e
      end

      def reset_session!
        return unless telemetry_enabled?

        ensure_session_closed!
        @session_id = @session_service.start_session(project_id: @default_project_id)
      rescue StandardError => e
        @error.puts("Session start telemetry failed: #{e.message}")
      end

      def ensure_session_closed!
        return unless telemetry_enabled?
        return if @session_id.nil?

        @session_service.end_session(session_id: @session_id)
        @session_id = nil
      rescue StandardError => e
        @error.puts("Session end telemetry failed: #{e.message}")
      end

      def safe_record_request(method:, tool_name:, project_id:, status:, duration_ms:)
        return unless telemetry_enabled?
        session_only_mode = @session_service.get_setting("privacy_mode", default: "session_only") == "session_only"

        @session_service.record_request(
          session_id: @session_id,
          method: method,
          tool_name: session_only_mode ? nil : tool_name,
          project_id: project_id,
          status: status,
          duration_ms: duration_ms
        )
      rescue StandardError => e
        @error.puts("Request telemetry failed: #{e.message}")
      end

      def telemetry_enabled?
        @telemetry_enabled
      end

      def elapsed_ms_since(start_time)
        return 0 unless start_time

        ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time) * 1000.0).round
      end

      def resolve_project_id(project_id)
        id = project_id.to_s.strip
        return @default_project_id if id.empty?

        id
      end

      def respond(id, result)
        message = {
          jsonrpc: "2.0",
          id: id,
          result: result
        }
        @output.puts(JSON.generate(message))
        @output.flush
      end

      def respond_error(id, code, message)
        payload = {
          jsonrpc: "2.0",
          id: id,
          error: { code: code, message: message }
        }
        @output.puts(JSON.generate(payload))
        @output.flush
      end
    end
  end
end

DevMemory::MCP::Server.new.start if $PROGRAM_NAME == __FILE__
