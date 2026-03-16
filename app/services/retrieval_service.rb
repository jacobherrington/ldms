require_relative "memory_service"
require_relative "profile_service"
require_relative "context_router_service"

module DevMemory
  module Services
    class RetrievalService
      def initialize(
        memory_service: MemoryService.new,
        profile_service: ProfileService.new,
        context_router: nil,
        workspace_root: Dir.pwd
      )
        @memory_service = memory_service
        @profile_service = profile_service
        @workspace_root = workspace_root
        @context_router = context_router || default_context_router(memory_service)
      end

      def get_context_packet(task:, project_id:, top_k: 8, memory_types: nil, ranking_profile: "balanced")
        context_payload = if @context_router
                            @context_router.build_context(
                              task: task,
                              project_id: project_id,
                              top_k: top_k,
                              ranking_profile: ranking_profile,
                              workspace_root: @workspace_root,
                              memory_types: memory_types
                            )
                          else
                            legacy_context(task: task, project_id: project_id, top_k: top_k, memory_types: memory_types, ranking_profile: ranking_profile)
                          end

        {
          task: task,
          project: project_id,
          ranking_profile: ranking_profile,
          developer_profile_summary: @profile_service.summary,
          retrieved_memories: context_payload[:retrieved_memories],
          repo_hints: context_payload[:repo_hints] || [],
          decision_hints: context_payload[:decision_hints] || [],
          git_context: context_payload[:git_context] || {},
          context_trace: context_payload[:context_trace]
        }
      end

      def debug_context(query:, project_id:, top_k: 8, memory_types: nil, ranking_profile: "balanced")
        packet = get_context_packet(
          task: query,
          project_id: project_id,
          top_k: top_k,
          memory_types: memory_types,
          ranking_profile: ranking_profile
        )
        {
          query: query,
          project_id: project_id,
          top_k: top_k,
          ranking_profile: ranking_profile,
          memory_types: memory_types || [],
          results: packet[:retrieved_memories],
          context_trace: packet[:context_trace],
          repo_hints: packet[:repo_hints]
        }
      end

      def record_feedback(memory_id:, helpful:, reason: nil)
        @memory_service.record_retrieval_feedback(
          memory_id: memory_id,
          helpful: helpful,
          reason: reason
        )
      end

      private

      def legacy_context(task:, project_id:, top_k:, memory_types:, ranking_profile:)
        project_memories = @memory_service.search_memory(
          query: task,
          project_id: project_id,
          top_k: top_k,
          memory_types: memory_types,
          ranking_profile: ranking_profile
        )

        global_memories = @memory_service.search_memory(
          query: task,
          project_id: nil,
          top_k: top_k,
          memory_types: memory_types,
          ranking_profile: ranking_profile
        ).reject { |row| row[:project_id] == project_id }

        {
          retrieved_memories: (project_memories + global_memories).uniq { |row| row[:id] }.first(top_k),
          context_trace: {
            selected_sources: ["memory"],
            rationale: { task: task, details: ["Context router unavailable; using memory-only retrieval."] }
          }
        }
      end

      def default_context_router(memory_service)
        return nil unless memory_service.class.name == "DevMemory::Services::MemoryService"

        ContextRouterService.new(memory_service: memory_service)
      end
    end
  end
end
