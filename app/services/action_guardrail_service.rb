module DevMemory
  module Services
    class ActionGuardrailService
      BLOCKED_PATTERNS = [
        /git\s+reset\s+--hard/i,
        /git\s+push\s+--force/i,
        /rm\s+-rf\s+\//i,
        /drop\s+table/i
      ].freeze

      def assess(workflow_type:, prompt:, dry_run:)
        issues = []
        text = [workflow_type, prompt].join(" ")
        BLOCKED_PATTERNS.each do |pattern|
          next unless text.match?(pattern)

          issues << "Blocked by guardrail pattern: #{pattern.inspect}"
        end

        {
          allowed: issues.empty?,
          dry_run: dry_run,
          issues: issues,
          risk_level: issues.empty? ? "low" : "high"
        }
      end
    end
  end
end
