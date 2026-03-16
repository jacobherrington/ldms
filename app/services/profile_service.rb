require "json"

module DevMemory
  module Services
    class ProfileService
      PROFILE_PATH = File.expand_path("../../config/developer_profile.json", __dir__)

      def initialize(profile_path: PROFILE_PATH)
        @profile_path = profile_path
      end

      def load_profile
        JSON.parse(File.read(@profile_path))
      end

      def summary
        profile = load_profile.fetch("developer", {})
        style = profile.fetch("style", {})
        architecture = profile.fetch("architecture", {})

        [
          "Languages: #{profile.fetch('languages', []).join(', ')}",
          "Frameworks: #{profile.fetch('frameworks', []).join(', ')}",
          "Style: small_functions=#{style['prefer_small_functions']}, explicit_types=#{style['prefer_explicit_types']}, comments=#{style['comments']}",
          "Architecture: monolith_first=#{architecture['prefer_monolith_first']}, avoid_premature_abstraction=#{architecture['avoid_premature_abstraction']}"
        ].join(" | ")
      end

      def retrieval_profiles
        load_profile.fetch("retrieval_profiles", {})
      end

      def default_retrieval_profile
        load_profile.fetch("default_retrieval_profile", "balanced")
      end

      def editable_profile
        developer = load_profile.fetch("developer", {})
        style = developer.fetch("style", {})
        {
          "languages" => Array(developer["languages"]).map(&:to_s),
          "frameworks" => Array(developer["frameworks"]).map(&:to_s),
          "style" => {
            "prefer_small_functions" => !!style["prefer_small_functions"],
            "prefer_explicit_types" => !!style["prefer_explicit_types"],
            "comments" => style.fetch("comments", "only_when_useful").to_s
          }
        }
      end

      def update_basic_profile!(payload)
        updates = normalize_profile_payload(payload)
        profile = load_profile
        profile["developer"] ||= {}
        profile["developer"]["languages"] = updates["languages"]
        profile["developer"]["frameworks"] = updates["frameworks"]
        profile["developer"]["style"] ||= {}
        profile["developer"]["style"]["prefer_small_functions"] = updates.fetch("style").fetch("prefer_small_functions")
        profile["developer"]["style"]["prefer_explicit_types"] = updates.fetch("style").fetch("prefer_explicit_types")
        profile["developer"]["style"]["comments"] = updates.fetch("style").fetch("comments")
        File.write(@profile_path, "#{JSON.pretty_generate(profile)}\n")
        editable_profile
      end

      private

      ALLOWED_COMMENTS = %w[only_when_useful concise detailed minimal].freeze

      def normalize_profile_payload(payload)
        source = payload.is_a?(Hash) ? payload : {}

        languages = normalize_text_list(source["languages"] || source[:languages], field: "languages")
        frameworks = normalize_text_list(source["frameworks"] || source[:frameworks], field: "frameworks")
        style_raw = source["style"] || source[:style] || {}
        raise ArgumentError, "style must be an object" unless style_raw.is_a?(Hash)

        comments = style_raw["comments"] || style_raw[:comments] || "only_when_useful"
        comments_text = comments.to_s.strip
        unless ALLOWED_COMMENTS.include?(comments_text)
          raise ArgumentError, "style.comments must be one of: #{ALLOWED_COMMENTS.join(', ')}"
        end

        {
          "languages" => languages,
          "frameworks" => frameworks,
          "style" => {
            "prefer_small_functions" => to_bool(style_raw, "prefer_small_functions"),
            "prefer_explicit_types" => to_bool(style_raw, "prefer_explicit_types"),
            "comments" => comments_text
          }
        }
      end

      def normalize_text_list(raw, field:)
        values = Array(raw).map { |value| value.to_s.strip }.reject(&:empty?).uniq
        raise ArgumentError, "#{field} must include at least one value" if values.empty?

        values
      end

      def to_bool(hash, key)
        value = hash[key] if hash.is_a?(Hash)
        value = hash[key.to_sym] if value.nil? && hash.is_a?(Hash)
        case value
        when true, false
          value
        when "true"
          true
        when "false"
          false
        when nil
          false
        else
          raise ArgumentError, "style.#{key} must be true or false"
        end
      end
    end
  end
end
