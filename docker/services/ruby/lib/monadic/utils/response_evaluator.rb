# frozen_string_literal: true

require 'json'
require 'net/http'
require 'uri'

module Monadic
  module Utils
    # ResponseEvaluator - AI-based response validation utility
    #
    # Uses an LLM (OpenAI by default) to evaluate whether a response
    # meets specified criteria. Returns both boolean result and confidence score.
    #
    # Use cases:
    # 1. Test validation: Verify AI responses match expected behavior
    # 2. App logic: Conditional branching based on response quality
    # 3. Quality assurance: Monitor response appropriateness
    #
    # @example Basic usage
    #   result = ResponseEvaluator.evaluate(
    #     response: "The validation was successful. Your ABC notation is correct.",
    #     expectation: "The response indicates successful tool execution",
    #     criteria: "Tool invocation success"
    #   )
    #   result[:match]      # => true
    #   result[:confidence] # => 0.95
    #
    # @example With context
    #   result = ResponseEvaluator.evaluate(
    #     response: ai_response,
    #     expectation: "AI should have called the validate_abc_syntax tool",
    #     criteria: "Tool was invoked",
    #     context: { tool_name: "validate_abc_syntax", prompt: original_prompt }
    #   )
    #
    class ResponseEvaluator
      # Default model for evaluation (cost-effective but capable)
      DEFAULT_MODEL = 'gpt-4o-mini'

      # Evaluation result structure
      EvaluationResult = Struct.new(:match, :confidence, :reasoning, :raw_response, keyword_init: true) do
        def to_h
          { match: match, confidence: confidence, reasoning: reasoning }
        end

        def success?
          match == true && confidence >= 0.7
        end

        def likely?
          confidence >= 0.5
        end
      end

      class << self
        # Evaluate a response against specified criteria
        #
        # @param response [String] The AI response to evaluate
        # @param expectation [String] What the response should contain/indicate
        # @param prompt [String] The original prompt that generated the response (recommended)
        # @param criteria [String] Brief description of what's being evaluated
        # @param context [Hash] Optional additional context (tool_name, etc.)
        # @param model [String] OpenAI model to use for evaluation
        # @param api_key [String] OpenAI API key (defaults to ENV)
        #
        # @return [EvaluationResult] Result with match, confidence, and reasoning
        #
        # @note Including the original prompt significantly improves evaluation accuracy
        #
        def evaluate(response:, expectation:, prompt: nil, criteria: nil, context: {}, model: DEFAULT_MODEL, api_key: nil)
          api_key ||= ENV['OPENAI_API_KEY']

          unless api_key && !api_key.empty?
            return EvaluationResult.new(
              match: nil,
              confidence: 0.0,
              reasoning: 'OpenAI API key not configured'
            )
          end

          evaluation_prompt = build_evaluation_prompt(
            response: response,
            expectation: expectation,
            prompt: prompt,
            criteria: criteria,
            context: context
          )

          result = call_openai(evaluation_prompt, model, api_key)
          parse_evaluation_result(result)
        rescue StandardError => e
          EvaluationResult.new(
            match: nil,
            confidence: 0.0,
            reasoning: "Evaluation error: #{e.message}"
          )
        end

        # Batch evaluate multiple criteria against a single response
        #
        # @param response [String] The AI response to evaluate
        # @param expectations [Array<Hash>] Array of { expectation:, criteria: } hashes
        # @param prompt [String] The original prompt that generated the response (recommended)
        # @param context [Hash] Optional additional context
        #
        # @return [Array<EvaluationResult>] Results for each expectation
        #
        def batch_evaluate(response:, expectations:, prompt: nil, context: {}, model: DEFAULT_MODEL, api_key: nil)
          expectations.map do |exp|
            evaluate(
              response: response,
              expectation: exp[:expectation],
              prompt: prompt,
              criteria: exp[:criteria],
              context: context,
              model: model,
              api_key: api_key
            )
          end
        end

        # Quick boolean check with default threshold
        #
        # @param response [String] The AI response to evaluate
        # @param expectation [String] What the response should contain/indicate
        # @param prompt [String] The original prompt that generated the response (recommended)
        # @param threshold [Float] Minimum confidence for true result (default: 0.7)
        #
        # @return [Boolean] true if expectation is met with sufficient confidence
        #
        def matches?(response:, expectation:, prompt: nil, threshold: 0.7, **options)
          result = evaluate(response: response, expectation: expectation, prompt: prompt, **options)
          result.match == true && result.confidence >= threshold
        end

        private

        def build_evaluation_prompt(response:, expectation:, prompt:, criteria:, context:)
          # Original prompt section - critical for accurate evaluation
          prompt_section = if prompt && !prompt.to_s.strip.empty?
                             <<~SECTION

                               ## Original User Prompt (IMPORTANT)
                               This is what the user asked for. Use this to understand the context and intent:
                               ```
                               #{prompt.to_s[0..1500]}
                               ```
                             SECTION
                           else
                             <<~SECTION

                               ## Note
                               No original prompt was provided. Evaluation accuracy may be reduced.
                             SECTION
                           end

          context_section = if context.any?
                              context_text = context.map { |k, v| "- #{k}: #{v}" }.join("\n")
                              "\n## Additional Context\n#{context_text}\n"
                            else
                              ''
                            end

          criteria_section = criteria ? "\n## Evaluation Criteria\n#{criteria}\n" : ''

          <<~PROMPT
            You are an objective evaluator. Analyze whether an AI response appropriately addresses the user's request.
            #{prompt_section}
            ## AI Response to Evaluate
            ```
            #{response.to_s[0..3000]}
            ```
            #{context_section}#{criteria_section}
            ## Expectation to Verify
            #{expectation}

            ## Evaluation Instructions
            1. First, understand what the user was asking for (from the Original User Prompt)
            2. Then, analyze whether the AI response meets the expectation
            3. Consider:
               - Did the AI attempt what was asked?
               - Does the response indicate success or failure?
               - Are there any error messages or refusals?
               - Is the response relevant to the original request?
            4. Assign a confidence score based on how clearly you can determine the match
            5. Provide brief reasoning

            ## Required Output Format (JSON only, no markdown)
            {
              "match": true or false,
              "confidence": 0.0 to 1.0,
              "reasoning": "Brief explanation of your assessment"
            }

            Confidence Guidelines:
            - 0.9-1.0: Absolutely clear match/non-match
            - 0.7-0.9: Strong evidence for match/non-match
            - 0.5-0.7: Some evidence but not conclusive
            - 0.3-0.5: Weak evidence, mostly uncertain
            - 0.0-0.3: Cannot determine from available information

            Important:
            - Return ONLY valid JSON, no markdown code blocks
            - If original prompt is missing, lower your confidence score accordingly
            - Be objective and thorough in your analysis
          PROMPT
        end

        def call_openai(prompt, model, api_key)
          uri = URI('https://api.openai.com/v1/chat/completions')

          request = Net::HTTP::Post.new(uri)
          request['Content-Type'] = 'application/json'
          request['Authorization'] = "Bearer #{api_key}"

          request.body = {
            model: model,
            messages: [
              { role: 'user', content: prompt }
            ],
            temperature: 0.0,
            max_tokens: 500
          }.to_json

          http = Net::HTTP.new(uri.host, uri.port)
          http.use_ssl = true
          http.open_timeout = 10
          http.read_timeout = 30

          response = http.request(request)

          unless response.is_a?(Net::HTTPSuccess)
            raise "OpenAI API error: #{response.code} - #{response.body[0..200]}"
          end

          parsed = JSON.parse(response.body)
          parsed.dig('choices', 0, 'message', 'content')
        end

        def parse_evaluation_result(content)
          return EvaluationResult.new(match: nil, confidence: 0.0, reasoning: 'Empty response') if content.nil? || content.empty?

          # Clean up potential markdown formatting
          cleaned = content.strip
                           .gsub(/^```json\s*/, '')
                           .gsub(/^```\s*/, '')
                           .gsub(/```$/, '')
                           .strip

          parsed = JSON.parse(cleaned, symbolize_names: true)

          EvaluationResult.new(
            match: parsed[:match],
            confidence: parsed[:confidence].to_f.clamp(0.0, 1.0),
            reasoning: parsed[:reasoning].to_s,
            raw_response: content
          )
        rescue JSON::ParserError => e
          # Try to extract information from unstructured response
          match = content.downcase.include?('true') && !content.downcase.include?('"match": false')
          EvaluationResult.new(
            match: match,
            confidence: 0.5,
            reasoning: "Could not parse structured response: #{e.message}",
            raw_response: content
          )
        end
      end
    end

    # Convenience alias
    RE = ResponseEvaluator
  end
end
