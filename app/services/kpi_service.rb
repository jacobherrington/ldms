require "time"
require_relative "../db/sqlite"

module DevMemory
  module Services
    class KpiService
      def initialize(db: DevMemory::DB::SQLite.connection)
        @db = db
      end

      def weekly_snapshot(project_id: nil)
        args = []
        project_clause = ""
        if project_id && !project_id.to_s.strip.empty?
          project_clause = " AND project_id = ?"
          args << project_id
        end

        week_ago = (Time.now.utc - (7 * 24 * 3600)).iso8601
        dissatisfaction = @db.get_first_row(
          <<~SQL,
            SELECT COUNT(*) AS count
            FROM memory_feedback mf
            JOIN memories m ON m.id = mf.memory_id
            WHERE datetime(mf.created_at) >= datetime(?)
              AND mf.feedback = 'not_helpful'
              #{project_clause}
          SQL
          [week_ago] + args
        )["count"].to_i

        helpful = @db.get_first_row(
          <<~SQL,
            SELECT COUNT(*) AS count
            FROM memory_feedback mf
            JOIN memories m ON m.id = mf.memory_id
            WHERE datetime(mf.created_at) >= datetime(?)
              AND mf.feedback = 'helpful'
              #{project_clause}
          SQL
          [week_ago] + args
        )["count"].to_i

        workflow_success = @db.get_first_row(
          <<~SQL,
            SELECT COUNT(*) AS count
            FROM workflow_runs
            WHERE datetime(created_at) >= datetime(?)
              AND status IN ('dry_run', 'planned')
              #{project_clause}
          SQL
          [week_ago] + args
        )["count"].to_i

        top_failures = @db.execute(
          <<~SQL,
            SELECT reason, COUNT(*) AS count
            FROM memory_feedback mf
            JOIN memories m ON m.id = mf.memory_id
            WHERE datetime(mf.created_at) >= datetime(?)
              AND mf.feedback = 'not_helpful'
              #{project_clause}
            GROUP BY reason
            ORDER BY count DESC
            LIMIT 5
          SQL
          [week_ago] + args
        ).map { |row| { reason: row["reason"], count: row["count"].to_i } }

        {
          timeframe: "7d",
          project_id: project_id,
          helpful_feedback_count: helpful,
          dissatisfaction_count: dissatisfaction,
          workflow_success_count: workflow_success,
          top_failure_modes: top_failures
        }
      end
    end
  end
end
