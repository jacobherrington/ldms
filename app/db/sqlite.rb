require "sqlite3"
require "fileutils"

module DevMemory
  module DB
    class SQLite
      DB_PATH = File.expand_path("../../data/memory.db", __dir__)

      class << self
        def connection
          @connection ||= begin
            FileUtils.mkdir_p(File.dirname(DB_PATH))
            db = ::SQLite3::Database.new(DB_PATH)
            db.results_as_hash = true
            db.busy_timeout = 3000
            db
          end
        end

        def init_schema!
          connection.execute_batch(<<~SQL)
            CREATE TABLE IF NOT EXISTS memories (
              id TEXT PRIMARY KEY,
              content TEXT NOT NULL,
              summary TEXT NOT NULL,
              memory_type TEXT NOT NULL,
              scope TEXT NOT NULL,
              project_id TEXT,
              source TEXT,
              confidence REAL DEFAULT 0.5,
              tags TEXT,
              created_at TEXT NOT NULL
            );

            CREATE TABLE IF NOT EXISTS decisions (
              id TEXT PRIMARY KEY,
              project_id TEXT NOT NULL,
              title TEXT NOT NULL,
              decision TEXT NOT NULL,
              rationale TEXT,
              created_at TEXT NOT NULL
            );

            CREATE TABLE IF NOT EXISTS sessions (
              id TEXT PRIMARY KEY,
              project_id TEXT NOT NULL,
              started_at TEXT NOT NULL,
              ended_at TEXT,
              summary TEXT
            );

            CREATE TABLE IF NOT EXISTS mcp_requests (
              id TEXT PRIMARY KEY,
              session_id TEXT,
              method TEXT NOT NULL,
              tool_name TEXT,
              project_id TEXT,
              status TEXT NOT NULL,
              duration_ms INTEGER,
              created_at TEXT NOT NULL,
              FOREIGN KEY(session_id) REFERENCES sessions(id) ON DELETE SET NULL
            );

            CREATE TABLE IF NOT EXISTS memory_feedback (
              id TEXT PRIMARY KEY,
              memory_id TEXT NOT NULL,
              feedback TEXT NOT NULL,
              reason TEXT,
              created_at TEXT NOT NULL,
              FOREIGN KEY(memory_id) REFERENCES memories(id) ON DELETE CASCADE
            );

            CREATE TABLE IF NOT EXISTS app_settings (
              key TEXT PRIMARY KEY,
              value TEXT NOT NULL,
              updated_at TEXT NOT NULL
            );

            CREATE TABLE IF NOT EXISTS repo_index_entries (
              id TEXT PRIMARY KEY,
              project_id TEXT NOT NULL,
              path TEXT NOT NULL,
              symbols TEXT,
              content_hash TEXT,
              indexed_at TEXT NOT NULL
            );

            CREATE TABLE IF NOT EXISTS workflow_runs (
              id TEXT PRIMARY KEY,
              project_id TEXT NOT NULL,
              workflow_type TEXT NOT NULL,
              prompt TEXT NOT NULL,
              dry_run INTEGER NOT NULL DEFAULT 1,
              status TEXT NOT NULL,
              preview_json TEXT,
              rollback_json TEXT,
              error_message TEXT,
              created_at TEXT NOT NULL,
              updated_at TEXT NOT NULL
            );

            CREATE TABLE IF NOT EXISTS vectors (
              memory_id TEXT PRIMARY KEY,
              embedding TEXT NOT NULL,
              project_id TEXT,
              memory_type TEXT NOT NULL,
              scope TEXT NOT NULL,
              confidence REAL DEFAULT 0.5,
              tags TEXT,
              created_at TEXT NOT NULL,
              FOREIGN KEY(memory_id) REFERENCES memories(id) ON DELETE CASCADE
            );

            CREATE INDEX IF NOT EXISTS idx_memories_project_id ON memories(project_id);
            CREATE INDEX IF NOT EXISTS idx_memories_memory_type ON memories(memory_type);
            CREATE INDEX IF NOT EXISTS idx_vectors_project_id ON vectors(project_id);
            CREATE INDEX IF NOT EXISTS idx_vectors_memory_type ON vectors(memory_type);
            CREATE INDEX IF NOT EXISTS idx_sessions_started_at ON sessions(started_at);
            CREATE INDEX IF NOT EXISTS idx_mcp_requests_session_id ON mcp_requests(session_id);
            CREATE INDEX IF NOT EXISTS idx_mcp_requests_created_at ON mcp_requests(created_at);
            CREATE INDEX IF NOT EXISTS idx_memory_feedback_memory_id ON memory_feedback(memory_id);
            CREATE INDEX IF NOT EXISTS idx_memory_feedback_created_at ON memory_feedback(created_at);
            CREATE INDEX IF NOT EXISTS idx_repo_index_project_path ON repo_index_entries(project_id, path);
            CREATE INDEX IF NOT EXISTS idx_workflow_runs_project_created ON workflow_runs(project_id, created_at);
          SQL

          ensure_column!("memories", "state", "TEXT DEFAULT 'active'")
          ensure_column!("memories", "relevance_score", "REAL DEFAULT 0")
          ensure_column!("memories", "updated_at", "TEXT")
          ensure_column!("memories", "is_archived", "INTEGER DEFAULT 0")
        end

        private

        def ensure_column!(table_name, column_name, column_sql)
          columns = connection.execute("PRAGMA table_info(#{table_name})").map { |row| row["name"] }
          return if columns.include?(column_name)

          connection.execute("ALTER TABLE #{table_name} ADD COLUMN #{column_name} #{column_sql}")
        end
      end
    end
  end
end
