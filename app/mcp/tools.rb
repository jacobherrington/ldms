require "json"
require_relative "../services/profile_service"
require_relative "../services/memory_service"
require_relative "../services/retrieval_service"
require_relative "../services/memory_loop_service"

module DevMemory
  module MCP
    class Tools
      def initialize(
        profile_service: DevMemory::Services::ProfileService.new,
        memory_service: DevMemory::Services::MemoryService.new,
        retrieval_service: DevMemory::Services::RetrievalService.new,
        memory_loop_service: nil,
        default_project_id: ENV["LDMS_PROJECT_ID"] || "default-project"
      )
        @profile_service = profile_service
        @memory_service = memory_service
        @retrieval_service = retrieval_service
        @memory_loop_service = memory_loop_service || DevMemory::Services::MemoryLoopService.new(memory_service: @memory_service)
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
                memory_types: {
                  type: "array",
                  items: { type: "string" }
                }
              }
            }
          },
          {
            name: "begin_task_context",
            description: "Build task-aware preflight context before implementation. Uses current workspace project_id by default.",
            inputSchema: {
              type: "object",
              required: ["task"],
              properties: {
                task: { type: "string" },
                task_type: {
                  type: "string",
                  enum: %w[feature bugfix refactor docs test ops auto],
                  default: "auto"
                },
                project_id: { type: ["string", "null"] },
                top_k: { type: "integer", default: 8 }
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
            name: "process_task_review",
            description: "Parse post-task review notes and auto-save durable memories by confidence threshold.",
            inputSchema: {
              type: "object",
              required: %w[task review_text],
              properties: {
                task: { type: "string" },
                review_text: { type: "string" },
                task_type: {
                  type: "string",
                  enum: %w[feature bugfix refactor docs test ops auto],
                  default: "auto"
                },
                project_id: { type: ["string", "null"] },
                auto_save_threshold: { type: "number", default: 0.85 },
                scope: { type: "string", default: "project" }
              }
            }
          },
          {
            name: "seed_developer_memories",
            description: "Seed curated memory entries based on developers you like.",
            inputSchema: {
              type: "object",
              required: ["developers"],
              properties: {
                developers: {
                  type: "array",
                  items: { type: "string" }
                },
                project_id: { type: ["string", "null"] },
                scope: { type: "string", default: "global" },
                confidence: { type: "number", default: 0.86 }
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
              memory_types: args["memory_types"]
            )
          )
        when "begin_task_context"
          payload(
            task_context: @retrieval_service.build_task_context(
              task: args.fetch("task"),
              project_id: resolve_project_id(args["project_id"]),
              task_type: args.fetch("task_type", "auto"),
              top_k: args.fetch("top_k", 8)
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
        when "process_task_review"
          payload(
            review_result: @memory_loop_service.process_task_review(
              task: args.fetch("task"),
              review_text: args.fetch("review_text"),
              project_id: resolve_project_id(args["project_id"]),
              task_type: args.fetch("task_type", "auto"),
              auto_save_threshold: args.fetch("auto_save_threshold", 0.85),
              scope: args.fetch("scope", "project")
            )
          )
        when "seed_developer_memories"
          payload(
            @memory_service.seed_developer_memories(
              developers: args.fetch("developers"),
              project_id: resolve_project_id(args["project_id"]),
              scope: args.fetch("scope", "global"),
              confidence: args.fetch("confidence", 0.86)
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
