# frozen_string_literal: true

module AutoForge
  module Utils
    class CodexResponseAnalyzer
      def self.analyze_response(content, existing_content: nil)
        return [:empty, nil] if content.nil? || content.to_s.strip.empty?

        cleaned = strip_markdown_blocks(content)

        if existing_content && valid_patch?(cleaned)
          [:patch, cleaned]
        elsif (html = extract_html(cleaned))
          [:full, html]
        else
          [:unknown, nil]
        end
      end

      class << self
        private

        def valid_patch?(content)
          has_diff_header = content.include?('---') && content.include?('+++')
          has_hunks = content.include?('@@')
          has_diff_header && has_hunks
        end

        def extract_html(content)
          if content.match?(/<!DOCTYPE/i)
            match = content.match(/<!DOCTYPE.*?<\/html>/mi)
            return match[0] if match
          end

          return content if content.match?(/<html/i) && content.match?(/<\/html>/i)

          nil
        end

        def strip_markdown_blocks(content)
          content.gsub(/```(?:html|diff|patch)?\n?/i, '')
                 .gsub(/```\n?/, '')
                 .strip
        end
      end
    end
  end
end
