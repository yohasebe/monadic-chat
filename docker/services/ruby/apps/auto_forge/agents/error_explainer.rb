# frozen_string_literal: true

module AutoForge
  module Agents
    class ErrorExplainer
      ERROR_PATTERNS = {
        /undefined is not (?:a )?function/i => {
          title: 'Function not found',
          explanation: 'The program is trying to call a function that does not exist.',
          impact: 'This feature will not work until the function is defined.',
          severity: :high
        },
        /Cannot read prop(?:erty)? .* of (?:null|undefined)/i => {
          title: 'Element not found',
          explanation: 'The application tried to use a page element that is missing.',
          impact: 'Some interactions may not respond.',
          severity: :high
        },
        /SyntaxError/i => {
          title: 'Code syntax error',
          explanation: 'There is an error in how the code is written.',
          impact: 'JavaScript execution stops until the error is fixed.',
          severity: :critical
        },
        /Failed to fetch/i => {
          title: 'Network request failed',
          explanation: 'The application could not retrieve data from an external source.',
          impact: 'Parts of the UI may not show the expected data.',
          severity: :medium
        },
        /Mixed Content/i => {
          title: 'Security warning',
          explanation: 'The page includes insecure content on a secure connection.',
          impact: 'Some browsers may block the content.',
          severity: :low
        },
        /TypeError:.*is not a constructor/i => {
          title: 'Invalid object creation',
          explanation: 'The code tried to create an object using an incorrect constructor.',
          impact: 'Initialisation of this feature fails.',
          severity: :high
        }
      }.freeze

      def explain_errors(debug_result)
        return [] unless debug_result.is_a?(Hash)

        explanations = []

        fetch_list(debug_result, :javascript_errors).each do |error|
          message = fetch_value(error, :message)
          next if message.nil? || message.strip.empty?

          explanation = find_explanation(message)
          explanations << explanation.merge(original: message, type: :error)
        end

        fetch_list(debug_result, :warnings).each do |warning|
          message = fetch_value(warning, :message)
          next if message.nil? || message.strip.empty?

          explanation = find_explanation(message)
          explanations << explanation.merge(original: message, type: :warning)
        end

        explanations
      end

      private

      def find_explanation(message)
        pattern = ERROR_PATTERNS.keys.find { |regex| message.match?(regex) }
        pattern ? ERROR_PATTERNS[pattern] : default_explanation
      end

      def fetch_list(record, key)
        Array(record[key] || record[key.to_s])
      end

      def fetch_value(record, key)
        record[key] || record[key.to_s]
      end

      def default_explanation
        {
          title: 'Technical error',
          explanation: 'An unexpected error occurred in the application.',
          impact: 'Some parts of the application may not work correctly.',
          severity: :medium
        }
      end
    end
  end
end
