require_relative "../db/sqlite"
require_relative "memory_service"
require_relative "repo_index_service"

module DevMemory
  module Services
    class ContextRouterService
      def initialize(
        memory_service: MemoryService.new,
        repo_index_service: RepoIndexService.new,
        db: DevMemory::DB::SQLite.connection
      )
        @memory_service = memory_service
        @repo_index_service = repo_index_service
        @db = db
      end

      def build_context(task:, project_id:, top_k:, ranking_profile:, workspace_root:, memory_types: nil)
        sources = choose_sources(task)

        memory_hits = @memory_service.search_memory(
          query: task,
          project_id: project_id,
          top_k: top_k,
          memory_types: memory_types,
          ranking_profile: ranking_profile
        )
        global_hits = @memory_service.search_memory(
          query: task,
          project_id: nil,
          top_k: top_k,
          memory_types: memory_types,
          ranking_profile: ranking_profile
        ).reject { |row| row[:project_id] == project_id }

        repo_hints = sources.include?("repo_index") ? @repo_index_service.query_index(project_id: project_id, query: task, limit: 8) : []
        decision_hints = sources.include?("decisions") ? recent_decisions(project_id: project_id, limit: 5) : []
        git_context = sources.include?("git") ? @repo_index_service.git_context(workspace_root: workspace_root) : {}

        {
          retrieved_memories: (memory_hits + global_hits).uniq { |row| row[:id] }.first(top_k),
          repo_hints: repo_hints,
          decision_hints: decision_hints,
          git_context: git_context,
          context_trace: {
            selected_sources: sources,
            rationale: rationale_for_sources(sources, task),
            memory_hit_count: memory_hits.length,
            repo_hint_count: repo_hints.length,
            decision_hint_count: decision_hints.length
          }
        }
      end

      private

      def choose_sources(task)
        text = task.to_s.downcase
        sources = ["memory"]
        if text.match?(/file|class|module|method|function|refactor|codebase|where|symbol/)
          sources << "repo_index"
        end
        sources << "decisions" if text.match?(/design|architecture|decision|tradeoff/)
        sources << "git" if text.match?(/regression|changed|recent|commit|diff|history/)
        sources.uniq
      end

      def rationale_for_sources(sources, task)
        {
          task: task,
          details: sources.map do |source|
            case source
            when "memory"
              "Always include prior memory for continuity and conventions."
            when "repo_index"
              "Task appears code-structure oriented; include symbol/path hints."
            when "decisions"
              "Task suggests design context; include recent architecture decisions."
            when "git"
              "Task suggests recency/change-awareness; include lightweight git context."
            else
              "Included by default."
            end
          end
        }
      end

      def recent_decisions(project_id:, limit:)
        @db.execute(
          <<~SQL,
            SELECT title, decision, rationale, created_at
            FROM decisions
            WHERE project_id = ?
            ORDER BY datetime(created_at) DESC
            LIMIT ?
          SQL
          [project_id, [limit.to_i, 1].max]
        ).map do |row|
          {
            title: row["title"],
            decision: row["decision"],
            rationale: row["rationale"],
            created_at: row["created_at"]
          }
        end
      end
    end
  end
end
