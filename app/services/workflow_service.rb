require "json"
require "securerandom"
require "time"
require_relative "../db/sqlite"
require_relative "action_guardrail_service"
require_relative "retrieval_service"
require_relative "repo_index_service"

module DevMemory
  module Services
    class WorkflowService
      WORKFLOW_TYPES = %w[implement_feature fix_failing_test refactor_module draft_pr_summary].freeze

      def initialize(
        db: DevMemory::DB::SQLite.connection,
        retrieval_service: RetrievalService.new,
        repo_index_service: RepoIndexService.new,
        guardrail_service: ActionGuardrailService.new
      )
        @db = db
        @retrieval_service = retrieval_service
        @repo_index_service = repo_index_service
        @guardrail_service = guardrail_service
      end

      def run(workflow_type:, prompt:, project_id:, dry_run: true)
        type = workflow_type.to_s
        raise ArgumentError, "Unknown workflow_type `#{workflow_type}`" unless WORKFLOW_TYPES.include?(type)

        guardrail = @guardrail_service.assess(workflow_type: type, prompt: prompt, dry_run: dry_run)
        run_id = SecureRandom.uuid
        now = Time.now.utc.iso8601
        preview = build_preview(workflow_type: type, prompt: prompt, project_id: project_id)
        rollback = build_rollback_metadata(project_id: project_id)

        status = if !guardrail[:allowed]
                   "blocked"
                 elsif dry_run
                   "dry_run"
                 else
                   "planned"
                 end

        @db.execute(
          <<~SQL,
            INSERT INTO workflow_runs (
              id, project_id, workflow_type, prompt, dry_run, status, preview_json, rollback_json, error_message, created_at, updated_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
          SQL
          [
            run_id,
            project_id.to_s.strip.empty? ? "default-project" : project_id,
            type,
            prompt.to_s,
            dry_run ? 1 : 0,
            status,
            JSON.generate(preview.merge(guardrail: guardrail)),
            JSON.generate(rollback),
            guardrail[:allowed] ? nil : guardrail[:issues].join(" | "),
            now,
            now
          ]
        )

        {
          run_id: run_id,
          status: status,
          dry_run: dry_run,
          guardrail: guardrail,
          preview: preview,
          rollback: rollback
        }
      end

      def list_runs(project_id: nil, limit: 25)
        sql = +"SELECT * FROM workflow_runs WHERE 1=1"
        args = []
        if project_id && !project_id.to_s.strip.empty?
          sql << " AND project_id = ?"
          args << project_id
        end
        sql << " ORDER BY datetime(created_at) DESC LIMIT ?"
        args << [limit.to_i, 1].max

        @db.execute(sql, args).map do |row|
          {
            id: row["id"],
            project_id: row["project_id"],
            workflow_type: row["workflow_type"],
            prompt: row["prompt"],
            dry_run: row["dry_run"].to_i == 1,
            status: row["status"],
            preview: parse_json(row["preview_json"]),
            rollback: parse_json(row["rollback_json"]),
            error_message: row["error_message"],
            created_at: row["created_at"],
            updated_at: row["updated_at"]
          }
        end
      end

      def recover_incomplete_runs!
        now = Time.now.utc.iso8601
        @db.execute(
          <<~SQL,
            UPDATE workflow_runs
            SET status = 'recovered', updated_at = ?, error_message = COALESCE(error_message, 'Recovered after restart')
            WHERE status IN ('running', 'queued')
          SQL
          [now]
        )
      end

      private

      def build_preview(workflow_type:, prompt:, project_id:)
        context = @retrieval_service.get_context_packet(
          task: prompt,
          project_id: project_id,
          top_k: 6
        )
        repo_hints = @repo_index_service.query_index(project_id: project_id, query: prompt, limit: 5)

        {
          workflow_type: workflow_type,
          prompt: prompt,
          suggested_steps: suggested_steps_for(workflow_type),
          context_packet: context,
          repo_hints: repo_hints
        }
      end

      def build_rollback_metadata(project_id:)
        {
          rollback_strategy: "git-safe-revert",
          project_id: project_id,
          note: "No files are auto-modified in V2 dry-run/planned mode."
        }
      end

      def suggested_steps_for(workflow_type)
        case workflow_type
        when "implement_feature"
          ["Clarify expected behavior", "Locate touchpoints", "Implement incrementally", "Add focused tests"]
        when "fix_failing_test"
          ["Reproduce failure", "Isolate root cause", "Patch behavior", "Re-run targeted suite"]
        when "refactor_module"
          ["Capture baseline behavior", "Refactor in small commits", "Run regression tests"]
        when "draft_pr_summary"
          ["Inspect changed files", "Extract intent", "Generate concise summary + test plan"]
        else
          ["Plan", "Execute", "Verify"]
        end
      end

      def parse_json(raw)
        return {} if raw.to_s.strip.empty?

        JSON.parse(raw)
      rescue JSON::ParserError
        {}
      end
    end
  end
end
