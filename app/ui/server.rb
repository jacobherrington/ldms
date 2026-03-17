#!/usr/bin/env ruby
# frozen_string_literal: true

require "erb"
require "json"
require "uri"
require "webrick"
require_relative "../db/sqlite"
require_relative "../services/memory_service"
require_relative "../services/profile_service"
require_relative "../services/retrieval_service"

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
        when ["GET", "/api/monitor"]
          render_monitor(req, res)
        when ["GET", "/api/profile"]
          render_profile(res)
        when ["GET", "/api/context_preview"]
          render_context_preview(req, res)
        when ["POST", "/memories"]
          create_memory(req, res)
        when ["POST", "/memories/delete"]
          delete_memory(req, res)
        when ["POST", "/decisions"]
          create_decision(req, res)
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
          updated_at: Time.now.utc.iso8601
        }

        res["Content-Type"] = "application/json"
        res.body = JSON.generate(payload)
      end

      def render_profile(res)
        payload = {
          profile: @profile_service.load_profile,
          profile_summary: @profile_service.summary
        }
        res["Content-Type"] = "application/json"
        res.body = JSON.generate(payload)
      end

      def render_context_preview(req, res)
        task = value_or_nil(req.query["task"])
        project_id = value_or_nil(req.query["project_id"]) || "default-project"
        raise ArgumentError, "task is required" if task.nil?

        packet = @retrieval_service.get_context_packet(task: task, project_id: project_id, top_k: 8)
        res["Content-Type"] = "application/json"
        res.body = JSON.generate(packet)
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

      def create_decision(req, res)
        @memory_service.log_decision(
          project_id: value_or_nil(req.query["project_id"]) || "default-project",
          title: req.query.fetch("title"),
          decision: req.query.fetch("decision"),
          rationale: req.query.fetch("rationale")
        )
        redirect_with_flash(res, req.query["project_id"], "Decision logged")
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
            </style>
          </head>
          <body>
            <h1>Local Dev Memory System</h1>
            <div class="sub">UI-first local memory management.</div>

            <% if @flash %>
              <div class="flash"><%= h(@flash) %></div>
            <% end %>

            <div class="panel">
              <strong>How To Use This Page</strong>
              <p class="muted">
                1) Set <span class="code">project_id</span> filter, 2) save memories as you work, 3) monitor live stats below.
                The dashboard auto-refreshes every 5 seconds.
              </p>
            </div>

            <form method="get" action="/" class="panel">
              <strong>Filters</strong>
              <label>Project ID</label>
              <input name="project_id" value="<%= h(@project_id) %>" placeholder="my-project">
              <label>Search Text</label>
              <input name="query" value="<%= h(@query) %>" placeholder="auth convention">
              <button type="submit">Apply Filters</button>
            </form>

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
                <div class="label">Updated</div>
                <div class="value" id="stat-updated-at" style="font-size:14px;">-</div>
              </div>
            </div>

            <div class="panel">
              <strong>Real-Time Activity</strong>
              <div class="muted" id="monitor-project">Project: <%= h(@project_id.empty? ? "all projects" : @project_id) %></div>
              <div class="muted" id="monitor-latest-memory">Latest memory: -</div>
              <div class="muted" id="monitor-latest-decision">Latest decision: -</div>
              <div class="muted" id="monitor-types">Type counts: -</div>
            </div>

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
                </div>
                <p><strong><%= h(memory[:summary]) %></strong></p>
                <p><%= h(memory[:content]) %></p>
                <div class="muted">project: <%= h(memory[:project_id].to_s) %> | created: <%= h(memory[:created_at].to_s) %></div>
                <div class="muted">tags: <%= h(memory[:tags].join(", ")) %></div>
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

                async function refreshMonitor() {
                  try {
                    const res = await fetch("/api/monitor" + query, { cache: "no-store" });
                    if (!res.ok) return;
                    const data = await res.json();

                    setText("stat-memory-count", String(data.memory_count ?? "-"));
                    setText("stat-decision-count", String(data.decision_count ?? "-"));
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
                    setText("monitor-types", "Type counts: " + formatTypeCounts(data.memory_type_counts));
                  } catch (_err) {
                    // Keep UI quiet if monitor polling fails transiently.
                  }
                }

                refreshMonitor();
                setInterval(refreshMonitor, 5000);
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
