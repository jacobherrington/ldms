#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "dotenv/load"
require_relative "../db/sqlite"
require_relative "tools"

module DevMemory
  module MCP
    class Server
      def initialize(
        input: $stdin,
        output: $stdout,
        error: $stderr,
        tools: nil
      )
        @input = input
        @output = output
        @error = error
        DevMemory::DB::SQLite.init_schema!
        @workspace_root = Dir.pwd
        @default_project_id = ENV["LDMS_PROJECT_ID"] || File.basename(@workspace_root)
        @tools = tools || Tools.new(default_project_id: @default_project_id)
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
      end

      private

      def handle_request(request)
        method = request[:method]
        params = request[:params] || {}
        id = request[:id]

        case method
        when "initialize"
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
        name = params.fetch(:name)
        args = stringify_keys(params[:arguments] || {})

        result = @tools.call(name, args)
        respond(id, result)
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
