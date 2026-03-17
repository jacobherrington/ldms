require_relative "memory_service"

module DevMemory
  module Services
    class MemoryLoopService
      DEFAULT_AUTO_SAVE_THRESHOLD = 0.85
      LINE_PREFIX_TYPE_MAP = {
        "preference" => "dev_preference",
        "convention" => "project_convention",
        "pattern" => "successful_pattern",
        "pitfall" => "anti_pattern",
        "bugfix" => "bug_fix_note",
        "decision" => "architecture_decision"
      }.freeze
      BASE_CONFIDENCE = {
        "dev_preference" => 0.88,
        "project_convention" => 0.87,
        "successful_pattern" => 0.86,
        "bug_fix_note" => 0.86,
        "architecture_decision" => 0.9,
        "anti_pattern" => 0.84
      }.freeze

      def initialize(memory_service: MemoryService.new)
        @memory_service = memory_service
      end

      def process_task_review(
        task:,
        project_id:,
        review_text:,
        task_type: "auto",
        scope: "project",
        auto_save_threshold: DEFAULT_AUTO_SAVE_THRESHOLD
      )
        threshold = auto_save_threshold.to_f
        candidates = extract_candidates(task: task, review_text: review_text, task_type: task_type)

        decisions = 0
        memories = 0
        suggestions = 0

        processed = candidates.map do |candidate|
          if candidate[:confidence] < threshold || !durable_candidate?(candidate[:content])
            suggestions += 1
            candidate.merge(status: "suggest")
          else
            result = persist_candidate(candidate: candidate, project_id: project_id, scope: scope, task: task)
            decisions += 1 if result[:result_type] == "decision"
            memories += 1 if result[:result_type] == "memory"
            candidate.merge(status: "saved", result: result)
          end
        end

        {
          status: "ok",
          task: task,
          task_type: task_type,
          auto_save_threshold: threshold,
          candidates: processed,
          saved_count: memories + decisions,
          saved_memory_count: memories,
          saved_decision_count: decisions,
          suggestion_count: suggestions
        }
      end

      private

      def extract_candidates(task:, review_text:, task_type:)
        lines = review_text.to_s.split("\n")
                           .map { |line| line.sub(/^\s*[-*]\s*/, "").strip }
                           .reject(&:empty?)
                           .first(12)

        candidates = lines.filter_map { |line| build_candidate(line) }
        return candidates unless candidates.empty?

        fallback_content = review_text.to_s.strip.gsub(/\s+/, " ")
        return [] if fallback_content.empty?

        [
          {
            memory_type: infer_memory_type(fallback_content, task_type),
            content: "#{task}: #{fallback_content}",
            confidence: 0.83,
            tags: %w[task_loop fallback]
          }
        ]
      end

      def build_candidate(line)
        if (match = line.match(/\A([a-z_ ]+)\s*:\s+(.+)\z/i))
          prefix = normalize_prefix(match[1])
          content = match[2].to_s.strip
          memory_type = LINE_PREFIX_TYPE_MAP[prefix]
          return nil if memory_type.nil? || content.empty?

          return candidate(memory_type: memory_type, content: content, source_tag: prefix)
        end

        memory_type = infer_memory_type(line, "auto")
        candidate(memory_type: memory_type, content: line, source_tag: "inferred")
      end

      def candidate(memory_type:, content:, source_tag:)
        {
          memory_type: memory_type,
          content: content,
          confidence: BASE_CONFIDENCE.fetch(memory_type, 0.84),
          tags: ["task_loop", source_tag]
        }
      end

      def infer_memory_type(text, task_type)
        content = "#{task_type} #{text}".downcase
        return "architecture_decision" if content.match?(/\b(decision|tradeoff|chose|architecture)\b/)
        return "dev_preference" if content.match?(/\b(prefer|preference|style)\b/)
        return "bug_fix_note" if content.match?(/\b(bug|fix|regression|incident)\b/)
        return "anti_pattern" if content.match?(/\b(avoid|anti-pattern|pitfall|don't)\b/)
        return "successful_pattern" if content.match?(/\b(pattern|workflow|checklist)\b/)

        "project_convention"
      end

      def persist_candidate(candidate:, project_id:, scope:, task:)
        if candidate[:memory_type] == "architecture_decision"
          title = summarize_for_title(candidate[:content], task: task)
          decision = candidate[:content]
          rationale = "Captured from task review loop for '#{task}'."
          decision_result = @memory_service.log_decision(
            project_id: project_id,
            title: title,
            decision: decision,
            rationale: rationale
          )
          return { result_type: "decision", decision_id: decision_result[:decision_id] }
        end

        memory_result = @memory_service.save_memory(
          content: candidate[:content],
          memory_type: candidate[:memory_type],
          scope: scope,
          project_id: project_id,
          confidence: candidate[:confidence],
          tags: candidate[:tags],
          source: "task_memory_loop"
        )
        { result_type: "memory", memory_id: memory_result[:memory_id] }
      end

      def summarize_for_title(content, task:)
        text = content.to_s.strip
        return "Task loop decision: #{task}" if text.empty?
        return text if text.length <= 72

        "#{text[0, 69]}..."
      end

      def normalize_prefix(prefix)
        prefix.to_s.downcase.strip.gsub(/\s+/, "_")
      end

      def durable_candidate?(content)
        text = content.to_s.downcase
        return false if text.empty?
        return false if text.match?(/\b(maybe|temporary|todo|wip|for now|investigate later)\b/)

        true
      end
    end
  end
end
