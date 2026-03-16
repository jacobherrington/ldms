require "digest"
require "json"
require "open3"
require "securerandom"
require "time"
require_relative "../db/sqlite"

module DevMemory
  module Services
    class RepoIndexService
      SUPPORTED_GLOBS = ["**/*.rb", "**/*.py", "**/*.js", "**/*.ts", "**/*.tsx", "**/*.md"].freeze
      IGNORE_PATHS = %w[node_modules vendor .git data tmp].freeze
      MAX_FILES = 500

      def initialize(db: DevMemory::DB::SQLite.connection)
        @db = db
      end

      def index_workspace(project_id:, workspace_root:, max_files: MAX_FILES)
        paths = discover_paths(workspace_root, max_files: max_files)
        now = Time.now.utc.iso8601

        @db.execute("DELETE FROM repo_index_entries WHERE project_id = ?", [project_id])
        paths.each do |abs_path|
          relative_path = abs_path.sub(%r{\A#{Regexp.escape(workspace_root)}/?}, "")
          content = safe_read(abs_path)
          symbols = extract_symbols(content)
          hash = Digest::SHA256.hexdigest(content)
          @db.execute(
            <<~SQL,
              INSERT INTO repo_index_entries (id, project_id, path, symbols, content_hash, indexed_at)
              VALUES (?, ?, ?, ?, ?, ?)
            SQL
            [SecureRandom.uuid, project_id, relative_path, symbols.to_json, hash, now]
          )
        end

        {
          status: "ok",
          project_id: project_id,
          indexed_files: paths.length,
          indexed_at: now
        }
      end

      def query_index(project_id:, query:, limit: 10)
        text = query.to_s.strip
        return [] if text.empty?

        like_term = "%#{text}%"
        rows = @db.execute(
          <<~SQL,
            SELECT path, symbols, indexed_at
            FROM repo_index_entries
            WHERE project_id = ?
              AND (path LIKE ? OR symbols LIKE ?)
            ORDER BY datetime(indexed_at) DESC
            LIMIT ?
          SQL
          [project_id, like_term, like_term, [limit.to_i, 1].max]
        )

        rows.map do |row|
          {
            path: row["path"],
            symbols: parse_json_array(row["symbols"]),
            indexed_at: row["indexed_at"]
          }
        end
      end

      def index_status(project_id:)
        count_row = @db.get_first_row(
          "SELECT COUNT(*) AS count, MAX(indexed_at) AS last_indexed_at FROM repo_index_entries WHERE project_id = ?",
          [project_id]
        )

        {
          project_id: project_id,
          indexed_file_count: count_row["count"].to_i,
          last_indexed_at: count_row["last_indexed_at"]
        }
      end

      def git_context(workspace_root:)
        status_out, _status_err, _status_code = Open3.capture3("git", "-C", workspace_root, "status", "--short")
        log_out, _log_err, _log_code = Open3.capture3("git", "-C", workspace_root, "log", "-1", "--oneline")

        {
          git_status_short: status_out.to_s.strip.split("\n").first(20),
          latest_commit: log_out.to_s.strip
        }
      rescue StandardError
        { git_status_short: [], latest_commit: nil }
      end

      private

      def discover_paths(workspace_root, max_files:)
        matches = SUPPORTED_GLOBS.flat_map { |glob| Dir.glob(File.join(workspace_root, glob)) }
        filtered = matches.select { |path| File.file?(path) && !ignored_path?(path, workspace_root) }
        filtered.sort.first(max_files)
      end

      def ignored_path?(abs_path, workspace_root)
        relative = abs_path.sub(%r{\A#{Regexp.escape(workspace_root)}/?}, "")
        IGNORE_PATHS.any? { |segment| relative.split(File::SEPARATOR).include?(segment) }
      end

      def safe_read(path)
        File.read(path, encoding: "UTF-8")
      rescue StandardError
        ""
      end

      def extract_symbols(content)
        symbols = []
        content.each_line do |line|
          stripped = line.strip
          if (match = stripped.match(/^class\s+([A-Za-z0-9_:]+)/))
            symbols << match[1]
          elsif (match = stripped.match(/^module\s+([A-Za-z0-9_:]+)/))
            symbols << match[1]
          elsif (match = stripped.match(/^def\s+([A-Za-z0-9_!?=]+)/))
            symbols << match[1]
          elsif (match = stripped.match(/^function\s+([A-Za-z0-9_]+)/))
            symbols << match[1]
          end
        end
        symbols.uniq.first(40)
      end

      def parse_json_array(raw)
        return [] if raw.to_s.strip.empty?

        parsed = JSON.parse(raw)
        parsed.is_a?(Array) ? parsed : []
      rescue JSON::ParserError
        []
      end
    end
  end
end
