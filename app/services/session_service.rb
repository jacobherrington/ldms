require "securerandom"
require "time"
require "json"
require_relative "../db/sqlite"

module DevMemory
  module Services
    class SessionService
      RECENT_WINDOW_SECONDS = 15 * 60
      ONBOARDING_STATE_KEY = "onboarding_state"

      def initialize(db: DevMemory::DB::SQLite.connection)
        @db = db
      end

      def start_session(project_id:)
        id = SecureRandom.uuid
        now = Time.now.utc.iso8601

        @db.execute(
          <<~SQL,
            INSERT INTO sessions (id, project_id, started_at, ended_at, summary)
            VALUES (?, ?, ?, NULL, NULL)
          SQL
          [id, normalize_project_id(project_id), now]
        )

        id
      end

      def end_session(session_id:)
        return if session_id.to_s.strip.empty?

        @db.execute(
          "UPDATE sessions SET ended_at = ? WHERE id = ?",
          [Time.now.utc.iso8601, session_id]
        )
      end

      def record_request(session_id:, method:, tool_name:, project_id:, status:, duration_ms:)
        id = SecureRandom.uuid
        now = Time.now.utc.iso8601

        @db.execute(
          <<~SQL,
            INSERT INTO mcp_requests (id, session_id, method, tool_name, project_id, status, duration_ms, created_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
          SQL
          [
            id,
            blank_to_nil(session_id),
            method.to_s,
            blank_to_nil(tool_name),
            normalize_project_id(project_id),
            status.to_s,
            duration_ms.to_i,
            now
          ]
        )
      end

      def monitor_snapshot(project_id: nil, limit: 10)
        id_filter = normalize_optional_project_id(project_id)
        active_count = count_active_sessions(id_filter)
        recent_count = count_recent_sessions(id_filter)
        request_stats = request_stats(id_filter)

        {
          active_session_count: active_count,
          recent_session_count: recent_count,
          request_ok_count: request_stats[:request_ok_count],
          request_error_count: request_stats[:request_error_count],
          avg_request_duration_ms: request_stats[:avg_request_duration_ms],
          latest_session: latest_session(id_filter),
          recent_sessions: recent_sessions(id_filter, limit: limit)
        }
      end

      def get_setting(key, default: nil)
        row = @db.get_first_row("SELECT value FROM app_settings WHERE key = ?", [key.to_s])
        return default unless row

        row["value"]
      end

      def set_setting(key:, value:)
        now = Time.now.utc.iso8601
        @db.execute(
          <<~SQL,
            INSERT INTO app_settings (key, value, updated_at)
            VALUES (?, ?, ?)
            ON CONFLICT(key) DO UPDATE SET
              value = excluded.value,
              updated_at = excluded.updated_at
          SQL
          [key.to_s, value.to_s, now]
        )
        { key: key.to_s, value: value.to_s }
      end

      def get_onboarding_state
        raw = get_setting(ONBOARDING_STATE_KEY, default: nil)
        parsed = parse_json(raw)
        base_onboarding_state.merge(parsed)
      end

      def update_onboarding_state(updates = {})
        current = get_onboarding_state
        merged = current.merge(stringify_keys(updates || {}))
        merged["steps"] = current.fetch("steps", {}).merge(stringify_keys((updates || {}).fetch(:steps, (updates || {}).fetch("steps", {}))))
        merged["updated_at"] = Time.now.utc.iso8601
        set_setting(key: ONBOARDING_STATE_KEY, value: JSON.generate(merged))
        merged
      end

      def mark_onboarding_complete
        update_onboarding_state(
          completed: true,
          completed_at: Time.now.utc.iso8601,
          steps: {
            env_checks: true,
            profile: true,
            seed: true,
            next_steps: true
          }
        )
      end

      def reset_onboarding_state
        state = base_onboarding_state.merge("updated_at" => Time.now.utc.iso8601)
        set_setting(key: ONBOARDING_STATE_KEY, value: JSON.generate(state))
        state
      end

      private

      def base_onboarding_state
        {
          "completed" => false,
          "dismissed" => false,
          "completed_at" => nil,
          "updated_at" => nil,
          "steps" => {
            "env_checks" => false,
            "profile" => false,
            "seed" => false,
            "next_steps" => false
          }
        }
      end

      def parse_json(raw)
        return {} if raw.to_s.strip.empty?

        value = JSON.parse(raw)
        return {} unless value.is_a?(Hash)

        stringify_keys(value)
      rescue JSON::ParserError
        {}
      end

      def stringify_keys(hash)
        hash.each_with_object({}) do |(key, value), out|
          out[key.to_s] = value.is_a?(Hash) ? stringify_keys(value) : value
        end
      end

      def normalize_project_id(project_id)
        text = project_id.to_s.strip
        return "default-project" if text.empty?

        text
      end

      def normalize_optional_project_id(project_id)
        text = project_id.to_s.strip
        return nil if text.empty?

        text
      end

      def blank_to_nil(value)
        text = value.to_s.strip
        return nil if text.empty?

        text
      end

      def count_active_sessions(project_id)
        row = execute_one(
          <<~SQL,
            SELECT COUNT(*) AS count
            FROM sessions
            WHERE ended_at IS NULL
              #{project_sql_filter("sessions.project_id", project_id)}
          SQL
          project_sql_args(project_id)
        )
        row["count"].to_i
      end

      def count_recent_sessions(project_id)
        threshold = (Time.now.utc - RECENT_WINDOW_SECONDS).iso8601
        args = [threshold] + project_sql_args(project_id)
        row = execute_one(
          <<~SQL,
            SELECT COUNT(*) AS count
            FROM sessions
            WHERE datetime(started_at) >= datetime(?)
              #{project_sql_filter("sessions.project_id", project_id)}
          SQL
          args
        )
        row["count"].to_i
      end

      def request_stats(project_id)
        row = execute_one(
          <<~SQL,
            SELECT
              SUM(CASE WHEN status = 'ok' THEN 1 ELSE 0 END) AS ok_count,
              SUM(CASE WHEN status = 'error' THEN 1 ELSE 0 END) AS error_count,
              AVG(duration_ms) AS avg_duration
            FROM mcp_requests
            WHERE 1=1
              #{project_sql_filter("project_id", project_id)}
          SQL
          project_sql_args(project_id)
        )

        {
          request_ok_count: row["ok_count"].to_i,
          request_error_count: row["error_count"].to_i,
          avg_request_duration_ms: row["avg_duration"] ? row["avg_duration"].round(2) : 0.0
        }
      end

      def latest_session(project_id)
        row = execute_one(
          <<~SQL,
            SELECT id, project_id, started_at, ended_at, summary
            FROM sessions
            WHERE 1=1
              #{project_sql_filter("project_id", project_id)}
            ORDER BY datetime(started_at) DESC
            LIMIT 1
          SQL
          project_sql_args(project_id)
        )
        return nil unless row

        row_to_session(row)
      end

      def recent_sessions(project_id, limit:)
        args = project_sql_args(project_id) + [[limit.to_i, 1].max]
        rows = @db.execute(
          <<~SQL,
            SELECT id, project_id, started_at, ended_at, summary
            FROM sessions
            WHERE 1=1
              #{project_sql_filter("project_id", project_id)}
            ORDER BY datetime(started_at) DESC
            LIMIT ?
          SQL
          args
        )
        rows.map { |row| row_to_session(row) }
      end

      def row_to_session(row)
        {
          id: row["id"],
          project_id: row["project_id"],
          started_at: row["started_at"],
          ended_at: row["ended_at"],
          summary: row["summary"]
        }
      end

      def execute_one(sql, args)
        @db.get_first_row(sql, args)
      end

      def project_sql_filter(column_name, project_id)
        return "" if project_id.nil?

        "AND #{column_name} = ?"
      end

      def project_sql_args(project_id)
        return [] if project_id.nil?

        [project_id]
      end
    end
  end
end
