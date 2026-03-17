require "json"
require_relative "../db/sqlite"
require_relative "memory_service"

module DevMemory
  module Services
    class BootstrapService
      SOURCE = "bootstrap_seed".freeze

      def initialize(
        memory_service: MemoryService.new,
        db: DevMemory::DB::SQLite.connection,
        project_root: File.expand_path("../..", __dir__),
        project_id: nil
      )
        @memory_service = memory_service
        @db = db
        @project_root = project_root
        @project_id = project_id || File.basename(project_root)
      end

      def run
        created_memory_ids = []
        skipped_entries = []

        bootstrap_entries.each do |entry|
          if memory_exists?(content: entry[:content], memory_type: entry[:memory_type], project_id: @project_id)
            skipped_entries << entry[:memory_type]
            next
          end

          result = @memory_service.save_memory(
            content: entry[:content],
            memory_type: entry[:memory_type],
            scope: "project",
            project_id: @project_id,
            confidence: entry[:confidence],
            tags: entry[:tags],
            source: SOURCE
          )
          created_memory_ids << result[:memory_id]
        end

        {
          status: "ok",
          project_id: @project_id,
          created_count: created_memory_ids.length,
          skipped_count: skipped_entries.length,
          created_memory_ids: created_memory_ids
        }
      end

      private

      def bootstrap_entries
        entries = []
        readme = read_optional("README.md")
        quick_setup = read_optional("docs/QUICK_SETUP.md")
        memory_rule = read_optional(".cursor/rules/memory.mdc")
        dev_style_rule = read_optional(".cursor/rules/dev-style.mdc")
        profile_json = read_optional("config/developer_profile.json")

        if readme && (quickstart = excerpt_line(readme, /^1\.\s+From this folder, run:/))
          entries << {
            memory_type: "project_convention",
            confidence: 0.85,
            tags: %w[bootstrap onboarding quickstart],
            content: "LDMS onboarding starts with one command: `bin/ldms install` before normal `bin/ldms` usage."
          }
        end

        if memory_rule && memory_rule.include?("begin_task_context")
          entries << {
            memory_type: "project_convention",
            confidence: 0.84,
            tags: %w[bootstrap retrieval workflow],
            content: "Before non-trivial coding tasks, run `begin_task_context` to load task-aware memory context."
          }
        end

        if dev_style_rule && (style_lines = bullet_lines(dev_style_rule)).any?
          entries << {
            memory_type: "project_convention",
            confidence: 0.82,
            tags: %w[bootstrap style],
            content: "Developer style preferences: #{style_lines.join('; ')}."
          }
        end

        if quick_setup && quick_setup.include?("Ollama")
          entries << {
            memory_type: "successful_pattern",
            confidence: 0.8,
            tags: %w[bootstrap runtime embeddings],
            content: "If embedding calls fail locally, keep working while starting Ollama (`ollama serve`) and retry retrieval."
          }
        end

        if profile_json
          profile = parse_json(profile_json)
          languages = Array(profile.dig("developer", "languages")).join(", ")
          frameworks = Array(profile.dig("developer", "frameworks")).join(", ")
          if !languages.empty? || !frameworks.empty?
            entries << {
              memory_type: "project_convention",
              confidence: 0.78,
              tags: %w[bootstrap profile],
              content: "Preferred stack for this project leans on languages: #{languages}; frameworks: #{frameworks}."
            }
          end
        end

        entries.uniq { |entry| [entry[:memory_type], entry[:content]] }
      end

      def read_optional(relative_path)
        absolute_path = File.join(@project_root, relative_path)
        return nil unless File.exist?(absolute_path)

        File.read(absolute_path)
      end

      def excerpt_line(content, regex)
        content.each_line.find { |line| line.match?(regex) }&.strip
      end

      def bullet_lines(content)
        content.each_line
               .map(&:strip)
               .select { |line| line.start_with?("- ") }
               .map { |line| line.sub("- ", "") }
               .reject(&:empty?)
               .first(4)
      end

      def parse_json(raw)
        JSON.parse(raw)
      rescue JSON::ParserError
        {}
      end

      def memory_exists?(content:, memory_type:, project_id:)
        sql = <<~SQL
          SELECT id FROM memories
          WHERE content = ?
            AND memory_type = ?
            AND COALESCE(project_id, '') = COALESCE(?, '')
          LIMIT 1
        SQL
        row = @db.get_first_row(sql, [content, memory_type, project_id])
        !row.nil?
      end
    end
  end
end
