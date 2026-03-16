#!/usr/bin/env ruby
# frozen_string_literal: true

require "erb"
require "json"
require "net/http"
require "open3"
require "uri"
require "webrick"
require_relative "../db/sqlite"
require_relative "../services/memory_service"
require_relative "../services/profile_service"
require_relative "../services/retrieval_service"
require_relative "../services/repo_index_service"
require_relative "../services/session_service"
require_relative "../services/workflow_service"
require_relative "../services/kpi_service"

module DevMemory
  module UI
    class Server
      DEFAULT_PORT = Integer(ENV.fetch("LDMS_UI_PORT", "4567"))
      DEFAULT_BIND = ENV.fetch("LDMS_UI_BIND", "127.0.0.1")

      def initialize(port: DEFAULT_PORT, bind: DEFAULT_BIND)
        DevMemory::DB::SQLite.init_schema!
        @memory_service = DevMemory::Services::MemoryService.new
        @profile_service = DevMemory::Services::ProfileService.new
        @retrieval_service = DevMemory::Services::RetrievalService.new(
          memory_service: @memory_service,
          profile_service: @profile_service
        )
        @repo_index_service = DevMemory::Services::RepoIndexService.new
        @session_service = DevMemory::Services::SessionService.new
        @workflow_service = DevMemory::Services::WorkflowService.new(
          retrieval_service: @retrieval_service,
          repo_index_service: @repo_index_service
        )
        @kpi_service = DevMemory::Services::KpiService.new
        @workflow_service.recover_incomplete_runs!
        @port = port
        @bind = bind
      end

      def start
        server = WEBrick::HTTPServer.new(
          Port: @port,
          BindAddress: @bind,
          AccessLog: [],
          Logger: WEBrick::Log.new($stderr, WEBrick::Log::WARN)
        )

        server.mount_proc("/") { |req, res| route(req, res) }
        trap("INT") { server.shutdown }
        trap("TERM") { server.shutdown }

        display_host = @bind == "0.0.0.0" ? "localhost" : @bind
        puts "LDMS UI running at http://#{display_host}:#{@port}"
        server.start
      end

      private

      def route(req, res)
        case [req.request_method, req.path]
        when ["GET", "/"]
          render_dashboard(req, res)
        when ["GET", "/api/onboarding/status"]
          render_onboarding_status(res)
        when ["GET", "/api/onboarding/wizard"]
          render_onboarding_wizard(req, res)
        when ["POST", "/api/onboarding/smoke"]
          run_onboarding_smoke(res)
        when ["POST", "/api/onboarding/seed"]
          run_onboarding_seed(req, res)
        when ["POST", "/api/onboarding/step"]
          update_onboarding_step(req, res)
        when ["POST", "/api/onboarding/complete"]
          complete_onboarding(res)
        when ["POST", "/api/onboarding/reset"]
          reset_onboarding(res)
        when ["POST", "/api/actions/doctor"]
          run_doctor_action(res)
        when ["POST", "/api/actions/smoke"]
          run_smoke_action(res)
        when ["POST", "/api/actions/preseed"]
          run_preseed_action(res)
        when ["POST", "/api/actions/global_snippet"]
          run_global_snippet_action(res)
        when ["POST", "/api/actions/global_install"]
          run_global_install_action(res)
        when ["POST", "/api/actions/global_setup"]
          run_global_setup_action(res)
        when ["GET", "/api/profile"]
          render_profile(res)
        when ["POST", "/api/profile/update"]
          update_profile(req, res)
        when ["GET", "/api/monitor"]
          render_monitor(req, res)
        when ["GET", "/api/control_center/status"]
          render_control_center_status(req, res)
        when ["POST", "/api/control_center/index"]
          trigger_repo_index(req, res)
        when ["POST", "/api/control_center/model_setup"]
          trigger_model_setup(res)
        when ["GET", "/api/rag_debug"]
          render_rag_debug(req, res)
        when ["GET", "/api/context_trace"]
          render_context_trace(req, res)
        when ["POST", "/api/retrieval/feedback"]
          record_retrieval_feedback(req, res)
        when ["POST", "/api/workflows/run"]
          run_workflow(req, res)
        when ["GET", "/api/workflows"]
          list_workflows(req, res)
        when ["GET", "/api/kpis"]
          render_kpis(req, res)
        when ["POST", "/memories"]
          create_memory(req, res)
        when ["POST", "/memories/delete"]
          delete_memory(req, res)
        when ["POST", "/memories/quality"]
          update_memory_quality(req, res)
        when ["POST", "/memories/update"]
          update_memory_metadata(req, res)
        when ["POST", "/decisions"]
          create_decision(req, res)
        when ["POST", "/settings/retrieval-profile"]
          update_retrieval_profile(req, res)
        when ["POST", "/settings/privacy-mode"]
          update_privacy_mode(req, res)
        else
          res.status = 404
          res["Content-Type"] = "text/plain"
          res.body = "Not Found"
        end
      rescue StandardError => e
        res.status = 500
        res["Content-Type"] = "text/plain"
        res.body = "UI error: #{e.message}"
      end

      def render_dashboard(req, res)
        @project_id = value_or_nil(req.query["project_id"]) || ""
        @query = value_or_nil(req.query["query"]) || ""
        @flash = value_or_nil(req.query["flash"])
        @advanced_mode = req.query.fetch("advanced", "0") == "1"
        @active_profile = current_retrieval_profile
        @privacy_mode = current_privacy_mode
        @retrieval_profiles = @profile_service.retrieval_profiles
        selected_project = value_or_nil(@project_id) || "default-project"
        @onboarding_status = onboarding_status(project_id: selected_project)
        @onboarding_state = @session_service.get_onboarding_state
        @editable_profile = @profile_service.editable_profile
        @memory_types = DevMemory::Services::MemoryService::MEMORY_TYPES
        @memories = @memory_service.list_memories(
          project_id: value_or_nil(@project_id),
          query: value_or_nil(@query),
          limit: 200
        )
        @decisions = @memory_service.list_decisions(project_id: value_or_nil(@project_id), limit: 100)

        res["Content-Type"] = "text/html"
        res.body = ERB.new(template, trim_mode: "-").result(binding)
      end

      def render_monitor(req, res)
        project_id = value_or_nil(req.query["project_id"])
        memories = @memory_service.list_memories(project_id: project_id, limit: 300)
        decisions = @memory_service.list_decisions(project_id: project_id, limit: 200)
        session_metrics = @session_service.monitor_snapshot(project_id: project_id, limit: 8)

        type_counts = Hash.new(0)
        memories.each { |memory| type_counts[memory[:memory_type]] += 1 }

        payload = {
          project_id: project_id,
          memory_count: memories.length,
          decision_count: decisions.length,
          memory_type_counts: type_counts,
          latest_memory: memories.first && {
            summary: memories.first[:summary],
            project_id: memories.first[:project_id],
            created_at: memories.first[:created_at]
          },
          latest_decision: decisions.first && {
            title: decisions.first[:title],
            project_id: decisions.first[:project_id],
            created_at: decisions.first[:created_at]
          },
          active_session_count: session_metrics[:active_session_count],
          recent_session_count: session_metrics[:recent_session_count],
          request_ok_count: session_metrics[:request_ok_count],
          request_error_count: session_metrics[:request_error_count],
          avg_request_duration_ms: session_metrics[:avg_request_duration_ms],
          latest_session: session_metrics[:latest_session],
          recent_sessions: session_metrics[:recent_sessions],
          updated_at: Time.now.utc.iso8601
        }

        res["Content-Type"] = "application/json"
        res.body = JSON.generate(payload)
      end

      def render_onboarding_status(res)
        payload = onboarding_status(project_id: "default-project")
        res["Content-Type"] = "application/json"
        res.body = JSON.generate(payload)
      end

      def render_onboarding_wizard(req, res)
        project_id = value_or_nil(req.query["project_id"]) || "default-project"
        payload = {
          status: onboarding_status(project_id: project_id),
          state: @session_service.get_onboarding_state,
          profile: @profile_service.editable_profile
        }
        res["Content-Type"] = "application/json"
        res.body = JSON.generate(payload)
      end

      def run_onboarding_smoke(res)
        payload = run_smoke_check
        res["Content-Type"] = "application/json"
        res.body = JSON.generate(payload)
      end

      def run_doctor_action(res)
        payload = command_action_payload(*%w[bash scripts/doctor.sh])
        res["Content-Type"] = "application/json"
        res.body = JSON.generate(payload)
      end

      def run_smoke_action(res)
        payload = command_action_payload(*%w[bash scripts/run.sh --smoke])
        res["Content-Type"] = "application/json"
        res.body = JSON.generate(payload)
      end

      def run_preseed_action(res)
        payload = command_action_payload(*%w[ruby scripts/preseed_ideas.rb])
        res["Content-Type"] = "application/json"
        res.body = JSON.generate(payload)
      end

      def run_global_snippet_action(res)
        payload = command_action_payload(*%w[bash scripts/install_global_cursor_mcp.sh --print])
        res["Content-Type"] = "application/json"
        res.body = JSON.generate(payload)
      end

      def run_global_install_action(res)
        payload = command_action_payload(*%w[bash scripts/install_global_cursor_mcp.sh --apply])
        res["Content-Type"] = "application/json"
        res.body = JSON.generate(payload)
      end

      def run_global_setup_action(res)
        payload = run_action_sequence(
          [
            { id: "doctor", command: %w[bash scripts/doctor.sh] },
            { id: "smoke", command: %w[bash scripts/run.sh --smoke] },
            { id: "preseed", command: %w[ruby scripts/preseed_ideas.rb] },
            { id: "global_install", command: %w[bash scripts/install_global_cursor_mcp.sh --apply] }
          ]
        )
        res["Content-Type"] = "application/json"
        res.body = JSON.generate(payload)
      end

      def run_onboarding_seed(req, res)
        project_id = value_or_nil(req.query["project_id"]) || "default-project"
        created = @memory_service.save_memory(
          content: "Run get_context_packet before major feature work.",
          memory_type: "project_convention",
          scope: "project",
          project_id: project_id,
          confidence: 0.9,
          tags: ["onboarding", "rag"]
        )
        debug = @retrieval_service.debug_context(
          query: "major feature work",
          project_id: project_id,
          top_k: 3,
          ranking_profile: current_retrieval_profile
        )
        res["Content-Type"] = "application/json"
        res.body = JSON.generate({ status: "ok", memory_id: created[:memory_id], debug: debug })
      rescue StandardError => e
        res.status = 422
        res["Content-Type"] = "application/json"
        res.body = JSON.generate({ status: "error", error: e.message })
      end

      def update_onboarding_step(req, res)
        step = value_or_nil(req.query["step"])
        completed = req.query.fetch("completed", "true") == "true"
        unless %w[env_checks profile seed next_steps].include?(step)
          raise ArgumentError, "Invalid onboarding step"
        end

        state = @session_service.update_onboarding_state(
          steps: { step => completed },
          dismissed: false
        )
        res["Content-Type"] = "application/json"
        res.body = JSON.generate({ status: "ok", state: state })
      rescue StandardError => e
        res.status = 422
        res["Content-Type"] = "application/json"
        res.body = JSON.generate({ status: "error", error: e.message })
      end

      def complete_onboarding(res)
        state = @session_service.mark_onboarding_complete
        res["Content-Type"] = "application/json"
        res.body = JSON.generate({ status: "ok", state: state })
      end

      def reset_onboarding(res)
        state = @session_service.reset_onboarding_state
        res["Content-Type"] = "application/json"
        res.body = JSON.generate({ status: "ok", state: state })
      end

      def render_profile(res)
        res["Content-Type"] = "application/json"
        res.body = JSON.generate(@profile_service.editable_profile)
      end

      def update_profile(req, res)
        payload = {
          "languages" => parse_tags(req.query["languages"]),
          "frameworks" => parse_tags(req.query["frameworks"]),
          "style" => {
            "prefer_small_functions" => req.query.fetch("prefer_small_functions", "false"),
            "prefer_explicit_types" => req.query.fetch("prefer_explicit_types", "false"),
            "comments" => req.query.fetch("comments", "only_when_useful")
          }
        }
        profile = @profile_service.update_basic_profile!(payload)
        @session_service.update_onboarding_state(steps: { "profile" => true })
        res["Content-Type"] = "application/json"
        res.body = JSON.generate({ status: "ok", profile: profile })
      rescue StandardError => e
        res.status = 422
        res["Content-Type"] = "application/json"
        res.body = JSON.generate({ status: "error", error: e.message })
      end

      def render_rag_debug(req, res)
        project_id = value_or_nil(req.query["project_id"])
        query = value_or_nil(req.query["query"]) || ""
        top_k = req.query.fetch("top_k", "8").to_i
        profile = value_or_nil(req.query["profile"]) || current_retrieval_profile
        memory_types = parse_tags(req.query["memory_types"])
        result = if query.empty?
                   { query: "", results: [], top_k: top_k, ranking_profile: profile, memory_types: memory_types }
                 else
                   @retrieval_service.debug_context(
                     query: query,
                     project_id: project_id,
                     top_k: [[top_k, 1].max, 20].min,
                     ranking_profile: profile,
                     memory_types: memory_types.empty? ? nil : memory_types
                   )
                 end
        res["Content-Type"] = "application/json"
        res.body = JSON.generate(result)
      rescue StandardError => e
        res.status = 422
        res["Content-Type"] = "application/json"
        res.body = JSON.generate({ status: "error", error: e.message })
      end

      def render_context_trace(req, res)
        project_id = value_or_nil(req.query["project_id"]) || "default-project"
        task = value_or_nil(req.query["task"]) || ""
        top_k = req.query.fetch("top_k", "8").to_i
        profile = value_or_nil(req.query["profile"]) || current_retrieval_profile
        packet = @retrieval_service.get_context_packet(
          task: task,
          project_id: project_id,
          top_k: [[top_k, 1].max, 20].min,
          ranking_profile: profile
        )
        res["Content-Type"] = "application/json"
        res.body = JSON.generate(
          {
            task: task,
            context_trace: packet[:context_trace],
            repo_hints: packet[:repo_hints],
            decision_hints: packet[:decision_hints],
            git_context: packet[:git_context]
          }
        )
      rescue StandardError => e
        res.status = 422
        res["Content-Type"] = "application/json"
        res.body = JSON.generate({ status: "error", error: e.message })
      end

      def render_control_center_status(req, res)
        project_id = value_or_nil(req.query["project_id"]) || "default-project"
        payload = {
          onboarding: onboarding_status(project_id: project_id),
          index_status: @repo_index_service.index_status(project_id: project_id),
          workflow_queue: @workflow_service.list_runs(project_id: project_id, limit: 10),
          monitor: @session_service.monitor_snapshot(project_id: project_id, limit: 5)
        }
        res["Content-Type"] = "application/json"
        res.body = JSON.generate(payload)
      end

      def trigger_repo_index(req, res)
        project_id = value_or_nil(req.query["project_id"]) || "default-project"
        workspace_root = value_or_nil(req.query["workspace_root"]) || Dir.pwd
        max_files = req.query.fetch("max_files", "500").to_i
        result = @repo_index_service.index_workspace(
          project_id: project_id,
          workspace_root: workspace_root,
          max_files: [[max_files, 50].max, 2000].min
        )
        res["Content-Type"] = "application/json"
        res.body = JSON.generate(result)
      rescue StandardError => e
        res.status = 422
        res["Content-Type"] = "application/json"
        res.body = JSON.generate({ status: "error", error: e.message })
      end

      def trigger_model_setup(res)
        stdout, stderr, status = Open3.capture3("ollama", "pull", "nomic-embed-text")
        res["Content-Type"] = "application/json"
        res.body = JSON.generate(
          {
            status: status.success? ? "ok" : "error",
            output: [stdout, stderr].join("\n").strip
          }
        )
      rescue StandardError => e
        res.status = 422
        res["Content-Type"] = "application/json"
        res.body = JSON.generate({ status: "error", error: e.message })
      end

      def run_workflow(req, res)
        workflow_type = req.query.fetch("workflow_type")
        prompt = req.query.fetch("prompt")
        project_id = value_or_nil(req.query["project_id"]) || "default-project"
        dry_run = req.query.fetch("dry_run", "true") == "true"
        result = @workflow_service.run(
          workflow_type: workflow_type,
          prompt: prompt,
          project_id: project_id,
          dry_run: dry_run
        )
        res["Content-Type"] = "application/json"
        res.body = JSON.generate(result)
      rescue StandardError => e
        res.status = 422
        res["Content-Type"] = "application/json"
        res.body = JSON.generate({ status: "error", error: e.message })
      end

      def list_workflows(req, res)
        project_id = value_or_nil(req.query["project_id"]) || "default-project"
        limit = req.query.fetch("limit", "25").to_i
        result = @workflow_service.list_runs(project_id: project_id, limit: limit)
        res["Content-Type"] = "application/json"
        res.body = JSON.generate({ workflow_runs: result })
      end

      def render_kpis(req, res)
        project_id = value_or_nil(req.query["project_id"]) || "default-project"
        result = @kpi_service.weekly_snapshot(project_id: project_id)
        res["Content-Type"] = "application/json"
        res.body = JSON.generate(result)
      end

      def create_memory(req, res)
        @memory_service.save_memory(
          content: req.query.fetch("content"),
          memory_type: req.query.fetch("memory_type"),
          scope: req.query.fetch("scope"),
          project_id: value_or_nil(req.query["project_id"]) || "default-project",
          confidence: req.query.fetch("confidence", "0.8").to_f,
          tags: parse_tags(req.query["tags"])
        )
        redirect_with_flash(res, req.query["project_id"], "Memory saved")
      end

      def delete_memory(req, res)
        @memory_service.delete_memory(memory_id: req.query.fetch("memory_id"))
        redirect_with_flash(res, req.query["project_id"], "Memory deleted")
      end

      def update_memory_quality(req, res)
        @memory_service.update_memory_quality(
          memory_id: req.query.fetch("memory_id"),
          action: req.query.fetch("action"),
          reason: value_or_nil(req.query["reason"])
        )
        redirect_with_flash(res, req.query["project_id"], "Memory quality updated")
      end

      def update_memory_metadata(req, res)
        @memory_service.update_memory_metadata(
          memory_id: req.query.fetch("memory_id"),
          summary: value_or_nil(req.query["summary"]),
          tags: parse_tags(req.query["tags"])
        )
        redirect_with_flash(res, req.query["project_id"], "Memory metadata updated")
      end

      def create_decision(req, res)
        @memory_service.log_decision(
          project_id: value_or_nil(req.query["project_id"]) || "default-project",
          title: req.query.fetch("title"),
          decision: req.query.fetch("decision"),
          rationale: req.query.fetch("rationale")
        )
        redirect_with_flash(res, req.query["project_id"], "Decision logged")
      end

      def record_retrieval_feedback(req, res)
        helpful = req.query.fetch("helpful", "true") == "true"
        result = @retrieval_service.record_feedback(
          memory_id: req.query.fetch("memory_id"),
          helpful: helpful,
          reason: value_or_nil(req.query["reason"])
        )
        res["Content-Type"] = "application/json"
        res.body = JSON.generate(result)
      rescue StandardError => e
        res.status = 422
        res["Content-Type"] = "application/json"
        res.body = JSON.generate({ status: "error", error: e.message })
      end

      def update_retrieval_profile(req, res)
        requested = value_or_nil(req.query["profile"]) || @profile_service.default_retrieval_profile
        @session_service.set_setting(key: "retrieval_profile", value: requested)
        redirect_with_flash(res, req.query["project_id"], "Retrieval profile updated")
      end

      def update_privacy_mode(req, res)
        mode = value_or_nil(req.query["mode"]) || "session_only"
        @session_service.set_setting(key: "privacy_mode", value: mode)
        redirect_with_flash(res, req.query["project_id"], "Privacy mode updated")
      end

      def redirect_with_flash(res, project_id, flash)
        query = URI.encode_www_form(
          project_id: project_id.to_s,
          flash: flash
        )
        res.status = 303
        res["Location"] = "/?#{query}"
      end

      def parse_tags(raw)
        raw.to_s.split(",").map(&:strip).reject(&:empty?)
      end

      def current_retrieval_profile
        @session_service.get_setting("retrieval_profile", default: @profile_service.default_retrieval_profile)
      end

      def current_privacy_mode
        @session_service.get_setting("privacy_mode", default: "session_only")
      end

      def onboarding_status(project_id:)
        docker_ok = command_available?("docker") && docker_compose_available?
        ollama_ok = command_available?("ollama")
        ollama_api_ok, model_ok = ollama_health
        smoke = mcp_initialize_ok?
        progress = onboarding_progress(project_id: project_id)
        state = @session_service.get_onboarding_state

        {
          checks: [
            { id: "docker", label: "Docker Compose installed", ok: docker_ok },
            { id: "ollama", label: "Ollama command available", ok: ollama_ok },
            { id: "model", label: "nomic-embed-text model available", ok: model_ok },
            { id: "mcp", label: "MCP initialize handshake", ok: smoke[:ok] }
          ],
          all_passed: docker_ok && ollama_ok && model_ok && smoke[:ok],
          progress: progress,
          state: state,
          details: {
            ollama_api_reachable: ollama_api_ok,
            mcp_output: smoke[:output]
          }
        }
      end

      def onboarding_progress(project_id:)
        memories = @memory_service.list_memories(project_id: project_id, limit: 1)
        index_status = @repo_index_service.index_status(project_id: project_id)
        workflows = @workflow_service.list_runs(project_id: project_id, limit: 1)
        {
          first_memory_saved: !memories.empty?,
          workspace_indexed: index_status.fetch(:indexed_file_count, 0).to_i > 0,
          first_workflow_run: !workflows.empty?
        }
      end

      def run_smoke_check
        stdout, stderr, status = Open3.capture3("bash", "scripts/run.sh", "--smoke")
        {
          ok: status.success?,
          output: [stdout, stderr].join("\n").strip
        }
      end

      def command_action_payload(*command)
        stdout, stderr, status = Open3.capture3(*command)
        {
          status: status.success? ? "ok" : "error",
          command: command.join(" "),
          output: [stdout, stderr].join("\n").strip
        }
      rescue StandardError => e
        {
          status: "error",
          command: command.join(" "),
          output: e.message
        }
      end

      def run_action_sequence(steps)
        results = []
        failed = false

        steps.each do |step|
          if failed
            results << {
              id: step.fetch(:id),
              status: "skipped",
              command: step.fetch(:command).join(" "),
              output: "skipped due to previous failure"
            }
            next
          end

          outcome = command_action_payload(*step.fetch(:command))
          results << outcome.merge(id: step.fetch(:id))
          failed = outcome.fetch(:status) != "ok"
        end

        {
          status: failed ? "error" : "ok",
          steps: results,
          output: results.map { |row| "#{row[:id]}=#{row[:status]}" }.join(" | ")
        }
      end

      def mcp_initialize_ok?
        request = '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}'
        stdout, stderr, status = Open3.capture3("bash", "-lc", "printf '#{request}\\n' | ruby app/mcp/server.rb")
        {
          ok: status.success? && stdout.include?('"protocolVersion"'),
          output: [stdout, stderr].join("\n").strip
        }
      end

      def command_available?(name)
        system("bash", "-lc", "command -v #{name} >/dev/null 2>&1")
      end

      def docker_compose_available?
        system("docker", "compose", "version", out: File::NULL, err: File::NULL)
      end

      def ollama_health
        uri = URI.parse("http://localhost:11434/api/tags")
        response = Net::HTTP.get_response(uri)
        return [false, false] unless response.code.to_i.between?(200, 299)

        payload = JSON.parse(response.body)
        names = Array(payload["models"]).map { |row| row["name"].to_s }
        [true, names.any? { |name| name.start_with?("nomic-embed-text") }]
      rescue StandardError
        [false, false]
      end

      def value_or_nil(value)
        text = value.to_s.strip
        return nil if text.empty?

        text
      end

      def template
        <<~HTML
          <!DOCTYPE html>
          <html>
          <head>
            <meta charset="utf-8">
            <title>LDMS UI</title>
            <style>
              body { font-family: -apple-system, system-ui, sans-serif; margin: 24px; color: #111; }
              h1 { margin-bottom: 8px; }
              .sub { color: #666; margin-bottom: 24px; }
              .row { display: flex; gap: 16px; flex-wrap: wrap; }
              .row-3 { display: grid; gap: 10px; grid-template-columns: repeat(auto-fill, minmax(220px, 1fr)); margin-bottom: 18px; }
              .card { border: 1px solid #ddd; border-radius: 8px; padding: 14px; margin-bottom: 12px; background: #fff; }
              .panel { border: 1px solid #ddd; border-radius: 8px; padding: 14px; margin-bottom: 18px; background: #fafafa; min-width: 320px; flex: 1; }
              .stat { border: 1px solid #ddd; border-radius: 8px; padding: 10px; background: #fff; }
              .stat .label { color: #555; font-size: 12px; margin-bottom: 4px; }
              .stat .value { font-size: 20px; font-weight: 600; }
              label { display: block; font-size: 12px; color: #555; margin-top: 8px; margin-bottom: 2px; }
              input, textarea, select { width: 100%; box-sizing: border-box; padding: 8px; border: 1px solid #ccc; border-radius: 6px; }
              textarea { min-height: 84px; }
              button { margin-top: 10px; border: 0; background: #111; color: #fff; padding: 8px 12px; border-radius: 6px; cursor: pointer; }
              .inline { display: inline; }
              .muted { color: #666; font-size: 12px; }
              .chip { display: inline-block; padding: 2px 8px; border-radius: 999px; background: #eee; margin-right: 6px; font-size: 12px; }
              .flash { padding: 10px; border-radius: 8px; background: #e8fff1; border: 1px solid #bee5cd; margin-bottom: 14px; }
              .code { font-family: ui-monospace, SFMono-Regular, Menlo, monospace; background: #f3f3f3; padding: 2px 6px; border-radius: 6px; }
              .banner { padding: 10px; border-radius: 8px; margin-bottom: 12px; }
              .banner-ok { background: #e8fff1; border: 1px solid #bee5cd; }
              .banner-warn { background: #fff6e8; border: 1px solid #f4d7a6; }
              .small-btn { margin-top: 6px; margin-right: 6px; background: #2a2a2a; }
              .rag-result { border-top: 1px solid #ddd; margin-top: 10px; padding-top: 10px; }
              .wizard-step { border: 1px solid #e1e1e1; border-radius: 8px; padding: 10px; margin-top: 8px; background: #fff; }
              .wizard-actions button { margin-right: 8px; }
            </style>
          </head>
          <body>
            <h1>Local Dev Memory System</h1>
            <div class="sub">Manage memories and decisions from one place.</div>

            <% if @flash %>
              <div class="flash"><%= h(@flash) %></div>
            <% end %>

            <% onboarding_pending = !@onboarding_status[:all_passed] %>
            <div class="banner <%= onboarding_pending ? "banner-warn" : "banner-ok" %>">
              <strong><%= onboarding_pending ? "Setup incomplete" : "Setup complete" %></strong>
              <div class="muted" id="onboarding-checks">
                <% @onboarding_status[:checks].each do |check| %>
                  <span><%= check[:ok] ? "PASS" : "MISSING" %> <%= h(check[:label]) %></span>
                <% end %>
              </div>
              <button class="small-btn" id="run-smoke-btn" type="button">Run one-click smoke</button>
              <button class="small-btn" id="refresh-onboarding-btn" type="button">Refresh setup checks</button>
              <button class="small-btn" id="seed-onboarding-btn" type="button">Create first memory + context preview</button>
              <button class="small-btn" id="reopen-onboarding-btn" type="button">Reopen onboarding wizard</button>
              <div class="muted" id="onboarding-output">Output: -</div>
            </div>

            <div class="panel" id="onboarding-wizard-panel">
              <strong>New Developer Onboarding Wizard</strong>
              <p class="muted">Complete the four steps to configure your profile and ship your first LDMS workflow.</p>
              <div class="wizard-step">
                <strong>Step 1: Environment checks</strong>
                <div class="muted" id="wizard-step-env">Pending</div>
                <button type="button" id="wizard-env-complete-btn">Mark step complete</button>
              </div>
              <div class="wizard-step">
                <strong>Step 2: Developer profile</strong>
                <label>Languages (comma separated)</label>
                <input id="profile-languages" value="<%= h(@editable_profile["languages"].join(", ")) %>" />
                <label>Frameworks (comma separated)</label>
                <input id="profile-frameworks" value="<%= h(@editable_profile["frameworks"].join(", ")) %>" />
                <label>Comments style</label>
                <select id="profile-comments">
                  <% ["only_when_useful", "concise", "detailed", "minimal"].each do |mode| %>
                    <option value="<%= h(mode) %>" <%= "selected" if @editable_profile.dig("style", "comments") == mode %>><%= h(mode) %></option>
                  <% end %>
                </select>
                <label>Prefer small functions</label>
                <select id="profile-small-functions">
                  <option value="true" <%= "selected" if @editable_profile.dig("style", "prefer_small_functions") %>>true</option>
                  <option value="false" <%= "selected" unless @editable_profile.dig("style", "prefer_small_functions") %>>false</option>
                </select>
                <label>Prefer explicit types</label>
                <select id="profile-explicit-types">
                  <option value="true" <%= "selected" if @editable_profile.dig("style", "prefer_explicit_types") %>>true</option>
                  <option value="false" <%= "selected" unless @editable_profile.dig("style", "prefer_explicit_types") %>>false</option>
                </select>
                <button type="button" id="profile-save-btn">Save profile</button>
                <div class="muted" id="profile-save-output">Profile: not saved yet</div>
              </div>
              <div class="wizard-step">
                <strong>Step 3: Create first memory</strong>
                <div class="muted" id="wizard-step-seed">Pending</div>
                <button type="button" id="wizard-seed-btn">Run onboarding seed</button>
              </div>
              <div class="wizard-step">
                <strong>Step 4: Next steps</strong>
                <div class="muted" id="wizard-next-steps">
                  [ ] Index workspace | [ ] Run first workflow | [ ] Open RAG Debug
                </div>
                <div class="wizard-actions">
                  <button type="button" id="wizard-open-rag-btn">Open advanced tools</button>
                  <button type="button" id="wizard-global-setup-btn">One-click global setup</button>
                  <button type="button" id="wizard-complete-btn">Complete onboarding</button>
                  <button type="button" id="wizard-reset-btn">Reset onboarding</button>
                </div>
              </div>
              <div class="muted" id="wizard-state-output">Wizard state: loading...</div>
            </div>

            <div class="panel">
              <strong>How To Use This Page</strong>
              <p class="muted">
                1) Set <span class="code">project_id</span> filter, 2) save memories as you work, 3) monitor live stats below.
                The dashboard auto-refreshes every 5 seconds.
              </p>
              <p class="muted">
                <strong>Mode:</strong>
                <% if @advanced_mode %>
                  Advanced mode is enabled. <a href="/?<%= URI.encode_www_form(project_id: @project_id, query: @query) %>">Switch to simple mode</a>.
                <% else %>
                  Simple mode is enabled. <a href="/?<%= URI.encode_www_form(project_id: @project_id, query: @query, advanced: "1") %>">Show advanced tools</a>.
                <% end %>
              </p>
              <p class="muted">
                Tip: use memory types intentionally:
                <span class="code">project_convention</span> for conventions,
                <span class="code">dev_preference</span> for your style,
                <span class="code">successful_pattern</span> for reusable wins.
              </p>
            </div>

            <% if @advanced_mode %>
              <div class="row">
                <form method="post" action="/settings/retrieval-profile" class="panel">
                  <strong>Retrieval Preset</strong>
                  <input type="hidden" name="project_id" value="<%= h(@project_id) %>">
                  <label>Profile</label>
                  <select name="profile">
                    <% @retrieval_profiles.each do |profile_id, profile| %>
                      <option value="<%= h(profile_id) %>" <%= "selected" if @active_profile == profile_id %>>
                        <%= h(profile["label"] || profile_id) %> - <%= h(profile["description"] || "") %>
                      </option>
                    <% end %>
                  </select>
                  <button type="submit">Save Preset</button>
                </form>

                <form method="post" action="/settings/privacy-mode" class="panel">
                  <strong>Privacy Mode</strong>
                  <input type="hidden" name="project_id" value="<%= h(@project_id) %>">
                  <label>Mode</label>
                  <select name="mode">
                    <option value="session_only" <%= "selected" if @privacy_mode == "session_only" %>>Session-only telemetry</option>
                    <option value="standard" <%= "selected" if @privacy_mode == "standard" %>>Standard local telemetry</option>
                  </select>
                  <p class="muted">Session-only mode avoids payload logging and keeps metrics aggregate-focused.</p>
                  <button type="submit">Save Privacy Mode</button>
                </form>
              </div>
            <% end %>

            <form method="get" action="/" class="panel">
              <strong>Filters</strong>
              <label>Project ID</label>
              <input name="project_id" value="<%= h(@project_id) %>" placeholder="my-project">
              <label>Search Text</label>
              <input name="query" value="<%= h(@query) %>" placeholder="auth convention">
              <input type="hidden" name="advanced" value="<%= @advanced_mode ? "1" : "0" %>">
              <button type="submit">Apply Filters</button>
            </form>

            <div class="panel">
              <strong>Quick Actions (UI-first)</strong>
              <div class="muted">Run setup tasks directly from this page.</div>
              <button type="button" id="quick-doctor-btn">Run Doctor</button>
              <button type="button" id="quick-smoke-btn">Run Smoke</button>
              <button type="button" id="quick-preseed-btn">Preseed Ideas</button>
              <button type="button" id="quick-global-setup-btn">One-click Global Setup</button>
              <button type="button" id="quick-global-snippet-btn">Show Global MCP Snippet</button>
              <button type="button" id="quick-global-install-btn">Install Global MCP</button>
              <div class="rag-result" id="quick-actions-output">No quick action run yet.</div>
            </div>

            <div class="row-3">
              <div class="stat">
                <div class="label">Memories</div>
                <div class="value" id="stat-memory-count">-</div>
              </div>
              <div class="stat">
                <div class="label">Decisions</div>
                <div class="value" id="stat-decision-count">-</div>
              </div>
              <div class="stat">
                <div class="label">Active Sessions</div>
                <div class="value" id="stat-active-sessions">-</div>
              </div>
              <div class="stat">
                <div class="label">Request Errors</div>
                <div class="value" id="stat-request-errors">-</div>
              </div>
              <div class="stat">
                <div class="label">Avg Request ms</div>
                <div class="value" id="stat-avg-duration">-</div>
              </div>
              <div class="stat">
                <div class="label">Updated</div>
                <div class="value" id="stat-updated-at" style="font-size:14px;">-</div>
              </div>
            </div>

            <div class="panel">
              <strong>Real-Time Activity</strong>
              <div class="muted" id="monitor-project">Project: <%= h(@project_id.empty? ? "all projects" : @project_id) %></div>
              <div class="muted" id="monitor-latest-memory">Latest memory: -</div>
              <div class="muted" id="monitor-latest-decision">Latest decision: -</div>
              <div class="muted" id="monitor-session-summary">Session activity: -</div>
              <div class="muted" id="monitor-latest-session">Latest session: -</div>
              <div class="muted" id="monitor-types">Type counts: -</div>
            </div>

            <% if @advanced_mode %>
              <div class="panel">
                <strong>RAG Debug</strong>
                <div class="muted">Inspect retrieval quality for a query and give helpful/not-helpful feedback.</div>
                <label>Query</label>
                <input id="rag-query" placeholder="How do we handle retries?" />
                <label>Top K</label>
                <input id="rag-top-k" value="8" />
                <label>Memory Types (comma separated)</label>
                <input id="rag-memory-types" placeholder="project_convention,successful_pattern" />
                <button type="button" id="run-rag-debug-btn">Run RAG Debug</button>
                <div class="rag-result" id="rag-debug-results">No query run yet.</div>
                <div class="rag-result" id="context-trace-results">No context trace yet.</div>
              </div>

              <div class="panel">
                <strong>Control Center</strong>
                <div class="muted">UI-first operations for indexing, model setup, workflows, and KPI visibility.</div>
                <button type="button" id="index-workspace-btn">Index Workspace</button>
                <button type="button" id="setup-model-btn">Setup Embedding Model</button>
                <label>Workflow Type</label>
                <select id="workflow-type">
                  <option value="implement_feature">Implement feature</option>
                  <option value="fix_failing_test">Fix failing test</option>
                  <option value="refactor_module">Refactor module</option>
                  <option value="draft_pr_summary">Draft PR summary</option>
                </select>
                <label>Workflow Prompt</label>
                <textarea id="workflow-prompt" placeholder="Describe the task goal and constraints"></textarea>
                <label>Dry Run</label>
                <select id="workflow-dry-run">
                  <option value="true">true</option>
                  <option value="false">false</option>
                </select>
                <button type="button" id="run-workflow-btn">Run Workflow</button>
                <div class="rag-result" id="control-center-output">No control-center action yet.</div>
                <div class="rag-result" id="workflow-history">No workflow history loaded.</div>
                <div class="rag-result" id="kpi-output">No KPI snapshot loaded.</div>
              </div>
            <% end %>

            <div class="row">
              <form method="post" action="/memories" class="panel">
                <strong>Add Memory</strong>
                <input type="hidden" name="project_id" value="<%= h(@project_id) %>">
                <label>Content</label>
                <textarea name="content" required></textarea>
                <label>Memory Type</label>
                <select name="memory_type">
                  <% @memory_types.each do |memory_type| %>
                    <option value="<%= h(memory_type) %>"><%= h(memory_type) %></option>
                  <% end %>
                </select>
                <label>Scope</label>
                <input name="scope" value="project">
                <label>Confidence (0-1)</label>
                <input name="confidence" value="0.8">
                <label>Tags (comma separated)</label>
                <input name="tags" placeholder="rails,auth,pattern">
                <button type="submit">Save Memory</button>
              </form>

              <form method="post" action="/decisions" class="panel">
                <strong>Log Decision</strong>
                <input type="hidden" name="project_id" value="<%= h(@project_id) %>">
                <label>Title</label>
                <input name="title" required>
                <label>Decision</label>
                <textarea name="decision" required></textarea>
                <label>Rationale</label>
                <textarea name="rationale" required></textarea>
                <button type="submit">Log Decision</button>
              </form>
            </div>

            <h2>Memories (<%= @memories.length %>)</h2>
            <% @memories.each do |memory| %>
              <div class="card">
                <div>
                  <span class="chip"><%= h(memory[:memory_type]) %></span>
                  <span class="chip"><%= h(memory[:scope]) %></span>
                  <span class="chip">confidence=<%= h(memory[:confidence].to_s) %></span>
                  <span class="chip">state=<%= h(memory[:state]) %></span>
                  <span class="chip">relevance=<%= h(memory[:relevance_score].round(2).to_s) %></span>
                </div>
                <p><strong><%= h(memory[:summary]) %></strong></p>
                <p><%= h(memory[:content]) %></p>
                <div class="muted">project: <%= h(memory[:project_id].to_s) %> | created: <%= h(memory[:created_at].to_s) %></div>
                <div class="muted">tags: <%= h(memory[:tags].join(", ")) %></div>
                <form method="post" action="/memories/quality" class="inline">
                  <input type="hidden" name="memory_id" value="<%= h(memory[:id]) %>">
                  <input type="hidden" name="project_id" value="<%= h(@project_id) %>">
                  <button type="submit" name="action" value="upvote">Thumbs Up</button>
                  <button type="submit" name="action" value="downvote">Thumbs Down</button>
                  <button type="submit" name="action" value="mark_stale">Mark Stale</button>
                  <button type="submit" name="action" value="archive">Archive</button>
                </form>
                <form method="post" action="/memories/update" class="panel">
                  <input type="hidden" name="memory_id" value="<%= h(memory[:id]) %>">
                  <input type="hidden" name="project_id" value="<%= h(@project_id) %>">
                  <label>Edit Summary</label>
                  <input name="summary" value="<%= h(memory[:summary]) %>">
                  <label>Edit Tags</label>
                  <input name="tags" value="<%= h(memory[:tags].join(", ")) %>">
                  <button type="submit">Save Metadata</button>
                </form>
                <form method="post" action="/memories/delete" class="inline">
                  <input type="hidden" name="memory_id" value="<%= h(memory[:id]) %>">
                  <input type="hidden" name="project_id" value="<%= h(@project_id) %>">
                  <button type="submit">Delete</button>
                </form>
              </div>
            <% end %>

            <h2>Decisions (<%= @decisions.length %>)</h2>
            <% @decisions.each do |decision| %>
              <div class="card">
                <p><strong><%= h(decision[:title]) %></strong></p>
                <p><%= h(decision[:decision]) %></p>
                <p class="muted">rationale: <%= h(decision[:rationale].to_s) %></p>
                <div class="muted">project: <%= h(decision[:project_id].to_s) %> | created: <%= h(decision[:created_at].to_s) %></div>
              </div>
            <% end %>
            <script>
              (function () {
                const projectId = "<%= h(@project_id) %>";
                const advancedMode = <%= @advanced_mode ? "true" : "false" %>;
                const query = projectId ? "?project_id=" + encodeURIComponent(projectId) : "";

                function formatTypeCounts(counts) {
                  const entries = Object.entries(counts || {});
                  if (entries.length === 0) return "-";
                  return entries.map(([k, v]) => k + ": " + v).join(" | ");
                }

                function setText(id, text) {
                  const node = document.getElementById(id);
                  if (node) node.textContent = text;
                }

                function formatLatestSession(session) {
                  if (!session) return "-";
                  const endText = session.ended_at ? "ended " + session.ended_at : "active";
                  return session.id + " (" + endText + ", started " + session.started_at + ")";
                }

                async function refreshMonitor() {
                  try {
                    const res = await fetch("/api/monitor" + query, { cache: "no-store" });
                    if (!res.ok) return;
                    const data = await res.json();

                    setText("stat-memory-count", String(data.memory_count ?? "-"));
                    setText("stat-decision-count", String(data.decision_count ?? "-"));
                    setText("stat-active-sessions", String(data.active_session_count ?? "-"));
                    setText("stat-request-errors", String(data.request_error_count ?? "-"));
                    setText("stat-avg-duration", String(data.avg_request_duration_ms ?? "-"));
                    setText("stat-updated-at", data.updated_at || "-");

                    const latestMemory = data.latest_memory
                      ? data.latest_memory.summary + " (" + data.latest_memory.created_at + ")"
                      : "-";
                    const latestDecision = data.latest_decision
                      ? data.latest_decision.title + " (" + data.latest_decision.created_at + ")"
                      : "-";

                    setText("monitor-project", "Project: " + (data.project_id || "all projects"));
                    setText("monitor-latest-memory", "Latest memory: " + latestMemory);
                    setText("monitor-latest-decision", "Latest decision: " + latestDecision);
                    setText(
                      "monitor-session-summary",
                      "Session activity: active="
                        + String(data.active_session_count ?? 0)
                        + " | recent="
                        + String(data.recent_session_count ?? 0)
                        + " | ok="
                        + String(data.request_ok_count ?? 0)
                        + " | errors="
                        + String(data.request_error_count ?? 0)
                    );
                    setText("monitor-latest-session", "Latest session: " + formatLatestSession(data.latest_session));
                    setText("monitor-types", "Type counts: " + formatTypeCounts(data.memory_type_counts));
                  } catch (_err) {
                    // Keep UI quiet if monitor polling fails transiently.
                  }
                }

                function formatChecks(checks) {
                  return (checks || []).map((check) => (check.ok ? "PASS " : "MISSING ") + check.label).join(" | ");
                }

                async function refreshOnboardingStatus() {
                  try {
                    const res = await fetch("/api/onboarding/status", { cache: "no-store" });
                    if (!res.ok) return;
                    const data = await res.json();
                    setText("onboarding-checks", formatChecks(data.checks));
                    setText("onboarding-output", "Output: " + (data.details?.mcp_output || "-"));
                  } catch (_err) {
                    setText("onboarding-output", "Output: failed to fetch onboarding status");
                  }
                }

                function stepLabel(done) {
                  return done ? "Completed" : "Pending";
                }

                async function refreshWizard() {
                  try {
                    const params = new URLSearchParams({ project_id: projectId || "default-project" });
                    const res = await fetch("/api/onboarding/wizard?" + params.toString(), { cache: "no-store" });
                    if (!res.ok) return;
                    const data = await res.json();
                    const state = data.state || {};
                    const steps = state.steps || {};
                    const progress = (data.status || {}).progress || {};

                    setText("wizard-step-env", stepLabel(Boolean(steps.env_checks)));
                    setText("wizard-step-seed", stepLabel(Boolean(steps.seed)));

                    const nextStepsText = [
                      progress.workspace_indexed ? "[x] Index workspace" : "[ ] Index workspace",
                      progress.first_workflow_run ? "[x] Run first workflow" : "[ ] Run first workflow",
                      advancedMode ? "[ ] Open RAG Debug" : "[ ] Open advanced tools"
                    ].join(" | ");
                    setText("wizard-next-steps", nextStepsText);

                    const completed = Boolean(state.completed);
                    setText(
                      "wizard-state-output",
                      completed ? "Wizard state: completed" : "Wizard state: in progress"
                    );
                    const panel = document.getElementById("onboarding-wizard-panel");
                    if (panel) panel.style.display = completed ? "none" : "block";
                  } catch (_err) {
                    setText("wizard-state-output", "Wizard state: failed to load");
                  }
                }

                async function runOneClickSmoke() {
                  setText("onboarding-output", "Output: running smoke...");
                  const res = await fetch("/api/onboarding/smoke", { method: "POST" });
                  const data = await res.json();
                  setText("onboarding-output", "Output: " + (data.output || "-"));
                  refreshOnboardingStatus();
                }

                async function seedOnboarding() {
                  const res = await fetch("/api/onboarding/seed", {
                    method: "POST",
                    headers: { "Content-Type": "application/x-www-form-urlencoded" },
                    body: new URLSearchParams({ project_id: projectId })
                  });
                  const data = await res.json();
                  if (data.status === "ok") {
                    setText("onboarding-output", "Output: seeded first memory and context preview");
                    await markWizardStep("seed", true);
                  } else {
                    setText("onboarding-output", "Output: " + (data.error || "failed"));
                  }
                }

                async function markWizardStep(step, completed) {
                  const res = await fetch("/api/onboarding/step", {
                    method: "POST",
                    headers: { "Content-Type": "application/x-www-form-urlencoded" },
                    body: new URLSearchParams({ step: step, completed: String(completed) })
                  });
                  const data = await res.json();
                  if (data.status !== "ok") {
                    setText("wizard-state-output", "Wizard state: " + (data.error || "failed to update step"));
                    return;
                  }
                  await refreshWizard();
                }

                async function saveProfile() {
                  const languages = ((document.getElementById("profile-languages") || {}).value || "").trim();
                  const frameworks = ((document.getElementById("profile-frameworks") || {}).value || "").trim();
                  const comments = ((document.getElementById("profile-comments") || {}).value || "only_when_useful").trim();
                  const smallFunctions = ((document.getElementById("profile-small-functions") || {}).value || "false").trim();
                  const explicitTypes = ((document.getElementById("profile-explicit-types") || {}).value || "false").trim();
                  const res = await fetch("/api/profile/update", {
                    method: "POST",
                    headers: { "Content-Type": "application/x-www-form-urlencoded" },
                    body: new URLSearchParams({
                      languages: languages,
                      frameworks: frameworks,
                      comments: comments,
                      prefer_small_functions: smallFunctions,
                      prefer_explicit_types: explicitTypes
                    })
                  });
                  const data = await res.json();
                  if (data.status === "ok") {
                    setText("profile-save-output", "Profile: saved");
                    await markWizardStep("profile", true);
                  } else {
                    setText("profile-save-output", "Profile error: " + (data.error || "failed"));
                  }
                }

                async function completeWizard() {
                  const res = await fetch("/api/onboarding/complete", { method: "POST" });
                  const data = await res.json();
                  if (data.status === "ok") {
                    setText("wizard-state-output", "Wizard state: completed");
                    await refreshWizard();
                  } else {
                    setText("wizard-state-output", "Wizard state: " + (data.error || "failed"));
                  }
                }

                async function resetWizard() {
                  const res = await fetch("/api/onboarding/reset", { method: "POST" });
                  const data = await res.json();
                  if (data.status === "ok") {
                    setText("wizard-state-output", "Wizard state: reset");
                    await refreshWizard();
                  } else {
                    setText("wizard-state-output", "Wizard state: " + (data.error || "failed"));
                  }
                }

                function openRagDebugStep() {
                  if (!advancedMode) {
                    const params = new URLSearchParams({ project_id: projectId, query: "<%= h(@query) %>", advanced: "1" });
                    window.location.href = "/?" + params.toString();
                    return;
                  }
                  const ragPanel = document.getElementById("rag-query");
                  if (ragPanel && typeof ragPanel.scrollIntoView === "function") {
                    ragPanel.scrollIntoView({ behavior: "smooth", block: "center" });
                    ragPanel.focus();
                  }
                  markWizardStep("next_steps", true);
                }

                function renderRagRows(results) {
                  if (!results || results.length === 0) return "No results.";
                  return results.map((row) => {
                    const reason = row.ranking_explanation
                      ? `sim=${row.ranking_explanation.factors.similarity}, conf=${row.ranking_explanation.factors.confidence}, rel=${row.ranking_explanation.factors.relevance}, fresh=${row.ranking_explanation.factors.freshness}`
                      : "n/a";
                    return `
                      <div class="card">
                        <div><span class="chip">${row.memory_type}</span><span class="chip">score=${Number(row.combined_score).toFixed(3)}</span></div>
                        <p><strong>${row.summary}</strong></p>
                        <p class="muted">why ranked: ${reason}</p>
                        <button type="button" class="small-btn" data-feedback-memory="${row.id}" data-helpful="true">Helpful</button>
                        <button type="button" class="small-btn" data-feedback-memory="${row.id}" data-helpful="false">Not helpful</button>
                      </div>
                    `;
                  }).join("");
                }

                async function runRagDebug() {
                  const queryText = (document.getElementById("rag-query") || {}).value || "";
                  const topK = (document.getElementById("rag-top-k") || {}).value || "8";
                  const memoryTypes = (document.getElementById("rag-memory-types") || {}).value || "";
                  const params = new URLSearchParams({
                    query: queryText,
                    top_k: topK,
                    project_id: projectId,
                    profile: "<%= h(@active_profile) %>",
                    memory_types: memoryTypes
                  });
                  const res = await fetch("/api/rag_debug?" + params.toString(), { cache: "no-store" });
                  const data = await res.json();
                  const container = document.getElementById("rag-debug-results");
                  if (container) container.innerHTML = renderRagRows(data.results);
                  const traceRes = await fetch("/api/context_trace?" + new URLSearchParams({
                    task: queryText,
                    top_k: topK,
                    project_id: projectId,
                    profile: "<%= h(@active_profile) %>"
                  }).toString(), { cache: "no-store" });
                  const traceData = await traceRes.json();
                  const traceContainer = document.getElementById("context-trace-results");
                  if (traceContainer) {
                    traceContainer.textContent = "Context trace: "
                      + JSON.stringify(traceData.context_trace || {}, null, 2);
                  }
                }

                async function sendFeedback(memoryId, helpful) {
                  const params = new URLSearchParams({
                    memory_id: memoryId,
                    helpful: String(helpful),
                    reason: helpful ? "helpful" : "irrelevant"
                  });
                  await fetch("/api/retrieval/feedback", {
                    method: "POST",
                    headers: { "Content-Type": "application/x-www-form-urlencoded" },
                    body: params
                  });
                }

                async function runQuickAction(path) {
                  const res = await fetch(path, { method: "POST" });
                  const data = await res.json();
                  if (Array.isArray(data.steps)) {
                    const summary = data.steps.map((step) => step.id + "=" + step.status).join(" | ");
                    setText("quick-actions-output", (data.status || "unknown") + ": " + summary);
                  } else {
                    setText("quick-actions-output", (data.status || "unknown") + ": " + (data.output || "-"));
                  }
                  if (path === "/api/actions/smoke") refreshOnboardingStatus();
                }

                async function indexWorkspace() {
                  const res = await fetch("/api/control_center/index", {
                    method: "POST",
                    headers: { "Content-Type": "application/x-www-form-urlencoded" },
                    body: new URLSearchParams({ project_id: projectId, workspace_root: "<%= h(Dir.pwd) %>" })
                  });
                  const data = await res.json();
                  setText("control-center-output", "Index result: " + JSON.stringify(data));
                }

                async function setupModel() {
                  const res = await fetch("/api/control_center/model_setup", { method: "POST" });
                  const data = await res.json();
                  setText("control-center-output", "Model setup: " + (data.status || "unknown"));
                }

                async function runWorkflow() {
                  const workflowType = (document.getElementById("workflow-type") || {}).value || "implement_feature";
                  const workflowPrompt = (document.getElementById("workflow-prompt") || {}).value || "";
                  const dryRun = (document.getElementById("workflow-dry-run") || {}).value || "true";
                  const res = await fetch("/api/workflows/run", {
                    method: "POST",
                    headers: { "Content-Type": "application/x-www-form-urlencoded" },
                    body: new URLSearchParams({
                      project_id: projectId,
                      workflow_type: workflowType,
                      prompt: workflowPrompt,
                      dry_run: dryRun
                    })
                  });
                  const data = await res.json();
                  setText("control-center-output", "Workflow result: " + JSON.stringify(data));
                  refreshWorkflowHistory();
                  refreshKpis();
                }

                async function refreshWorkflowHistory() {
                  const res = await fetch("/api/workflows?" + new URLSearchParams({ project_id: projectId }).toString(), { cache: "no-store" });
                  const data = await res.json();
                  setText("workflow-history", "Workflow history: " + JSON.stringify(data.workflow_runs || []));
                }

                async function refreshKpis() {
                  const res = await fetch("/api/kpis?" + new URLSearchParams({ project_id: projectId }).toString(), { cache: "no-store" });
                  const data = await res.json();
                  setText("kpi-output", "KPI snapshot: " + JSON.stringify(data));
                }

                refreshMonitor();
                refreshOnboardingStatus();
                refreshWizard();
                setInterval(refreshMonitor, 5000);
                setInterval(refreshOnboardingStatus, 10000);
                setInterval(refreshWizard, 12000);
                if (advancedMode) {
                  refreshWorkflowHistory();
                  refreshKpis();
                  setInterval(refreshWorkflowHistory, 15000);
                  setInterval(refreshKpis, 30000);
                }

                const smokeBtn = document.getElementById("run-smoke-btn");
                if (smokeBtn) smokeBtn.addEventListener("click", runOneClickSmoke);

                const refreshBtn = document.getElementById("refresh-onboarding-btn");
                if (refreshBtn) refreshBtn.addEventListener("click", refreshOnboardingStatus);

                const seedBtn = document.getElementById("seed-onboarding-btn");
                if (seedBtn) seedBtn.addEventListener("click", seedOnboarding);

                const envStepBtn = document.getElementById("wizard-env-complete-btn");
                if (envStepBtn) envStepBtn.addEventListener("click", () => markWizardStep("env_checks", true));

                const profileSaveBtn = document.getElementById("profile-save-btn");
                if (profileSaveBtn) profileSaveBtn.addEventListener("click", saveProfile);

                const wizardSeedBtn = document.getElementById("wizard-seed-btn");
                if (wizardSeedBtn) wizardSeedBtn.addEventListener("click", seedOnboarding);

                const wizardCompleteBtn = document.getElementById("wizard-complete-btn");
                if (wizardCompleteBtn) wizardCompleteBtn.addEventListener("click", completeWizard);

                const wizardResetBtn = document.getElementById("wizard-reset-btn");
                if (wizardResetBtn) wizardResetBtn.addEventListener("click", resetWizard);

                const wizardOpenRagBtn = document.getElementById("wizard-open-rag-btn");
                if (wizardOpenRagBtn) wizardOpenRagBtn.addEventListener("click", openRagDebugStep);

                const wizardGlobalSetupBtn = document.getElementById("wizard-global-setup-btn");
                if (wizardGlobalSetupBtn) wizardGlobalSetupBtn.addEventListener("click", () => runQuickAction("/api/actions/global_setup"));

                const reopenOnboardingBtn = document.getElementById("reopen-onboarding-btn");
                if (reopenOnboardingBtn) reopenOnboardingBtn.addEventListener("click", resetWizard);

                const ragBtn = document.getElementById("run-rag-debug-btn");
                if (ragBtn) ragBtn.addEventListener("click", runRagDebug);

                const indexBtn = document.getElementById("index-workspace-btn");
                if (indexBtn) indexBtn.addEventListener("click", indexWorkspace);

                const modelBtn = document.getElementById("setup-model-btn");
                if (modelBtn) modelBtn.addEventListener("click", setupModel);

                const workflowBtn = document.getElementById("run-workflow-btn");
                if (workflowBtn) workflowBtn.addEventListener("click", runWorkflow);

                const quickDoctorBtn = document.getElementById("quick-doctor-btn");
                if (quickDoctorBtn) quickDoctorBtn.addEventListener("click", () => runQuickAction("/api/actions/doctor"));

                const quickSmokeBtn = document.getElementById("quick-smoke-btn");
                if (quickSmokeBtn) quickSmokeBtn.addEventListener("click", () => runQuickAction("/api/actions/smoke"));

                const quickPreseedBtn = document.getElementById("quick-preseed-btn");
                if (quickPreseedBtn) quickPreseedBtn.addEventListener("click", () => runQuickAction("/api/actions/preseed"));

                const quickGlobalSetupBtn = document.getElementById("quick-global-setup-btn");
                if (quickGlobalSetupBtn) quickGlobalSetupBtn.addEventListener("click", () => runQuickAction("/api/actions/global_setup"));

                const quickGlobalSnippetBtn = document.getElementById("quick-global-snippet-btn");
                if (quickGlobalSnippetBtn) quickGlobalSnippetBtn.addEventListener("click", () => runQuickAction("/api/actions/global_snippet"));

                const quickGlobalInstallBtn = document.getElementById("quick-global-install-btn");
                if (quickGlobalInstallBtn) quickGlobalInstallBtn.addEventListener("click", () => runQuickAction("/api/actions/global_install"));

                document.addEventListener("click", function (event) {
                  const target = event.target;
                  if (!target || !target.dataset || !target.dataset.feedbackMemory) return;
                  sendFeedback(target.dataset.feedbackMemory, target.dataset.helpful === "true");
                });
              })();
            </script>
          </body>
          </html>
        HTML
      end

      def h(value)
        ERB::Util.html_escape(value.to_s)
      end
    end
  end
end

DevMemory::UI::Server.new.start if $PROGRAM_NAME == __FILE__
