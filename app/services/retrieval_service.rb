require_relative "memory_service"
require_relative "profile_service"

module DevMemory
  module Services
    class RetrievalService
      TASK_TYPE_MEMORY_TYPES = {
        "feature" => %w[project_convention architecture_decision successful_pattern],
        "bugfix" => %w[bug_fix_note anti_pattern project_convention],
        "refactor" => %w[architecture_decision project_convention anti_pattern],
        "docs" => %w[project_convention successful_pattern],
        "test" => %w[bug_fix_note successful_pattern project_convention],
        "ops" => %w[architecture_decision bug_fix_note successful_pattern]
      }.freeze

      def initialize(
        memory_service: MemoryService.new,
        profile_service: ProfileService.new
      )
        @memory_service = memory_service
        @profile_service = profile_service
      end

      def get_context_packet(task:, project_id:, top_k: 8, memory_types: nil)
        context_payload = memory_only_context(
          task: task,
          project_id: project_id,
          top_k: top_k,
          memory_types: memory_types
        )

        {
          task: task,
          project: project_id,
          developer_profile_summary: @profile_service.summary,
          retrieved_memories: context_payload[:retrieved_memories],
          context_trace: context_payload[:context_trace]
        }
      end

      def debug_context(query:, project_id:, top_k: 8, memory_types: nil)
        packet = get_context_packet(
          task: query,
          project_id: project_id,
          top_k: top_k,
          memory_types: memory_types
        )
        {
          query: query,
          project_id: project_id,
          top_k: top_k,
          memory_types: memory_types || [],
          results: packet[:retrieved_memories],
          context_trace: packet[:context_trace]
        }
      end

      def build_task_context(task:, project_id:, task_type: "auto", top_k: 8)
        normalized_task_type, inferred_from = resolve_task_type(task: task, task_type: task_type)
        selected_memory_types = TASK_TYPE_MEMORY_TYPES.fetch(normalized_task_type, nil)
        packet = get_context_packet(
          task: task,
          project_id: project_id,
          top_k: top_k,
          memory_types: selected_memory_types
        )
        memories = packet[:retrieved_memories]

        {
          task: task,
          project: project_id,
          task_type: normalized_task_type,
          developer_profile_summary: packet[:developer_profile_summary],
          retrieved_memories: memories,
          context_trace: packet[:context_trace].merge(
            selected_memory_types: selected_memory_types || [],
            task_type_inference: {
              requested: task_type.to_s.strip.empty? ? "auto" : task_type.to_s,
              resolved: normalized_task_type,
              inferred_from: inferred_from
            }
          ),
          working_context: {
            conventions: pick_summaries(memories, %w[project_convention successful_pattern], 3),
            decisions: pick_summaries(memories, %w[architecture_decision], 3),
            pitfalls: pick_summaries(memories, %w[anti_pattern bug_fix_note], 2),
            trace: {
              selected_memory_types: selected_memory_types || [],
              rationale: "Task-aware retrieval for preflight context."
            }
          }
        }
      end

      private

      def memory_only_context(task:, project_id:, top_k:, memory_types:)
        project_memories = @memory_service.search_memory(
          query: task,
          project_id: project_id,
          top_k: top_k,
          memory_types: memory_types
        )

        global_memories = @memory_service.search_memory(
          query: task,
          project_id: nil,
          top_k: top_k,
          memory_types: memory_types
        ).reject { |row| row[:project_id] == project_id }

        {
          retrieved_memories: (project_memories + global_memories).uniq { |row| row[:id] }.first(top_k),
          context_trace: {
            selected_sources: ["memory"],
            rationale: { task: task, details: ["Using memory-only retrieval context."] }
          }
        }
      end

      def resolve_task_type(task:, task_type:)
        requested = task_type.to_s.strip.downcase
        return [requested, nil] if TASK_TYPE_MEMORY_TYPES.key?(requested)
        return infer_task_type(task), "task_keywords" if requested.empty? || requested == "auto"

        ["feature", "fallback_to_feature"]
      end

      def infer_task_type(task)
        text = task.to_s.downcase
        return "bugfix" if text.match?(/\b(bug|fix|error|regression|broken|failure|debug|hotfix|incident)\b/)
        return "refactor" if text.match?(/\b(refactor|cleanup|simplify|restructure|extract|rename)\b/)
        return "test" if text.match?(/\b(test|spec|coverage|flaky|assert|regression test)\b/)
        return "docs" if text.match?(/\b(doc|docs|readme|guide|onboard|documentation|how-to)\b/)
        return "ops" if text.match?(/\b(deploy|infra|ops|ci|pipeline|monitor|observability|rollback)\b/)
        return "feature" if text.match?(/\b(add|implement|build|create|introduce|support|enable)\b/)

        "feature"
      end

      def pick_summaries(memories, memory_types, limit)
        memories
          .select { |row| memory_types.include?(row[:memory_type].to_s) }
          .map { |row| row[:summary].to_s.strip.empty? ? row[:content].to_s.strip : row[:summary].to_s.strip }
          .reject(&:empty?)
          .uniq
          .first(limit)
      end
    end
  end
end
