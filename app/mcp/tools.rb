require "json"
require_relative "../services/profile_service"
require_relative "../services/memory_service"
require_relative "../services/retrieval_service"
require_relative "../services/repo_index_service"
require_relative "../services/workflow_service"

module DevMemory
  module MCP
    class Tools
      def initialize(
        profile_service: DevMemory::Services::ProfileService.new,
        memory_service: DevMemory::Services::MemoryService.new,
        retrieval_service: DevMemory::Services::RetrievalService.new,
        repo_index_service: DevMemory::Services::RepoIndexService.new,
        workflow_service: DevMemory::Services::WorkflowService.new,
        default_project_id: ENV["LDMS_PROJECT_ID"] || "default-project"
      )
        @profile_service = profile_service
        @memory_service = memory_service
        @retrieval_service = retrieval_service
        @repo_index_service = repo_index_service
        @workflow_service = workflow_service
        @default_project_id = default_project_id
      end

      def list
        [
          {
            name: "get_dev_profile",
            description: "Return developer profile and compact summary.",
            inputSchema: {
              type: "object",
              properties: {}
            }
          },
          {
            name: "search_memory",
            description: "Search memory using vector retrieval. Uses current workspace project_id by default.",
            inputSchema: {
              type: "object",
              required: ["query"],
              properties: {
                query: { type: "string" },
                project_id: { type: ["string", "null"] },
                top_k: { type: "integer", default: 8 },
                memory_types: {
                  type: "array",
                  items: { type: "string" }
                }
              }
            }
          },
          {
            name: "get_context_packet",
            description: "Build project + profile context for a task. Uses current workspace project_id by default.",
            inputSchema: {
              type: "object",
              required: ["task"],
              properties: {
                task: { type: "string" },
                project_id: { type: ["string", "null"] },
                top_k: { type: "integer", default: 8 },
                ranking_profile: { type: "string", default: "balanced" },
                memory_types: {
                  type: "array",
                  items: { type: "string" }
                }
              }
            }
          },
          {
            name: "index_repo",
            description: "Index workspace files and symbols for context routing.",
            inputSchema: {
              type: "object",
              properties: {
                project_id: { type: ["string", "null"] },
                workspace_root: { type: "string" },
                max_files: { type: "integer", default: 500 }
              }
            }
          },
          {
            name: "run_workflow",
            description: "Create a workflow run with guardrails and preview.",
            inputSchema: {
              type: "object",
              required: %w[workflow_type prompt],
              properties: {
                project_id: { type: ["string", "null"] },
                workflow_type: { type: "string" },
                prompt: { type: "string" },
                dry_run: { type: "boolean", default: true }
              }
            }
          },
          {
            name: "list_workflows",
            description: "List recent workflow runs.",
            inputSchema: {
              type: "object",
              properties: {
                project_id: { type: ["string", "null"] },
                limit: { type: "integer", default: 25 }
              }
            }
          },
          {
            name: "save_memory",
            description: "Persist a memory and index embedding. Uses current workspace project_id by default.",
            inputSchema: {
              type: "object",
              required: %w[content memory_type scope],
              properties: {
                content: { type: "string" },
                memory_type: { type: "string" },
                scope: { type: "string" },
                project_id: { type: ["string", "null"] },
                confidence: { type: "number", default: 0.8 },
                tags: { type: "array", items: { type: "string" } }
              }
            }
          },
          {
            name: "log_decision",
            description: "Persist architecture/project decision and rationale. Uses current workspace project_id by default.",
            inputSchema: {
              type: "object",
              required: %w[title decision rationale],
              properties: {
                project_id: { type: ["string", "null"] },
                title: { type: "string" },
                decision: { type: "string" },
                rationale: { type: "string" }
              }
            }
          }
        ]
      end

      def call(name, arguments)
        args = arguments || {}

        case name
        when "get_dev_profile"
          payload(
            profile: @profile_service.load_profile,
            profile_summary: @profile_service.summary
          )
        when "search_memory"
          payload(
            results: @memory_service.search_memory(
              query: args.fetch("query"),
              project_id: resolve_project_id(args["project_id"]),
              top_k: args.fetch("top_k", 8),
              memory_types: args["memory_types"]
            )
          )
        when "get_context_packet"
          payload(
            context_packet: @retrieval_service.get_context_packet(
              task: args.fetch("task"),
              project_id: resolve_project_id(args["project_id"]),
              top_k: args.fetch("top_k", 8),
              ranking_profile: args.fetch("ranking_profile", "balanced"),
              memory_types: args["memory_types"]
            )
          )
        when "index_repo"
          payload(
            @repo_index_service.index_workspace(
              project_id: resolve_project_id(args["project_id"]),
              workspace_root: args.fetch("workspace_root", Dir.pwd),
              max_files: args.fetch("max_files", 500)
            )
          )
        when "run_workflow"
          payload(
            @workflow_service.run(
              workflow_type: args.fetch("workflow_type"),
              prompt: args.fetch("prompt"),
              project_id: resolve_project_id(args["project_id"]),
              dry_run: args.fetch("dry_run", true)
            )
          )
        when "list_workflows"
          payload(
            workflow_runs: @workflow_service.list_runs(
              project_id: resolve_project_id(args["project_id"]),
              limit: args.fetch("limit", 25)
            )
          )
        when "save_memory"
          payload(
            @memory_service.save_memory(
              content: args.fetch("content"),
              memory_type: args.fetch("memory_type"),
              scope: args.fetch("scope"),
              project_id: resolve_project_id(args["project_id"]),
              confidence: args.fetch("confidence", 0.8),
              tags: args.fetch("tags", [])
            )
          )
        when "log_decision"
          payload(
            @memory_service.log_decision(
              project_id: resolve_project_id(args["project_id"]),
              title: args.fetch("title"),
              decision: args.fetch("decision"),
              rationale: args.fetch("rationale")
            )
          )
        else
          raise ArgumentError, "Unknown tool `#{name}`"
        end
      end

      private

      def payload(obj)
        {
          content: [
            {
              type: "text",
              text: JSON.pretty_generate(obj)
            }
          ],
          structuredContent: obj
        }
      end

      def resolve_project_id(project_id)
        id = project_id.to_s.strip
        return @default_project_id if id.empty?

        id
      end
    end
  end
end
