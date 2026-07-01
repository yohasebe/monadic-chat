# frozen_string_literal: true

module Monadic
  module Utils
    # Normalizes provider-specific token usage from an API response into one
    # common schema: { input:, output:, reasoning:, cached:, total: } (Integer
    # or nil where a provider does not report it).
    #
    # Pure function, no IO — takes the parsed JSON response Hash (string keys,
    # as JSON.parse produces) and probes the provider's known usage location.
    # This consolidates the usage fields the vendor helpers already receive
    # (see memory: provider-usage-token-accounting-design) so downstream
    # accounting/display/context code reads one shape regardless of provider.
    #
    # Notes:
    # - `output` already includes reasoning tokens for reasoning models (e.g.
    #   OpenAI completion_tokens counts reasoning_tokens); `reasoning` is the
    #   informational sub-count, so `total` sums input+output only.
    # - Streaming responses surface usage only in the final chunk (and OpenAI
    #   needs stream_options:{include_usage:true}); that capture is the caller's
    #   job — this module only maps whatever usage object it is handed.
    module UsageNormalizer
      EMPTY = { input: nil, output: nil, reasoning: nil, cached: nil, total: nil }.freeze

      # provider: case-insensitive provider key (openai, anthropic/claude,
      # gemini/google, cohere, mistral, deepseek, grok/xai, ollama).
      # raw: parsed response Hash (full response or its usage object).
      def self.extract(provider, raw)
        return EMPTY.dup unless raw.is_a?(Hash)

        case provider.to_s.downcase
        when "gemini", "google"
          m = raw["usageMetadata"] || raw["usage_metadata"] || raw
          build(
            input: int(m["promptTokenCount"]),
            output: int(m["candidatesTokenCount"]),
            reasoning: int(m["thoughtsTokenCount"]),
            cached: int(m["cachedContentTokenCount"]),
            total: int(m["totalTokenCount"])
          )
        when "ollama"
          # Ollama reports counts at the top level of the final response object.
          build(input: int(raw["prompt_eval_count"]), output: int(raw["eval_count"]))
        else
          # OpenAI (chat + responses), Anthropic/Claude, Cohere, Mistral,
          # DeepSeek, Grok(xAI) all nest a "usage" object. Key names vary
          # (input_tokens vs prompt_tokens, cohere nests under "tokens"), so
          # probe the known aliases.
          u = raw["usage"].is_a?(Hash) ? raw["usage"] : raw
          nested = u["tokens"].is_a?(Hash) ? u["tokens"] : nil # cohere v2

          input  = int(u["input_tokens"]) || int(u["prompt_tokens"]) || (nested && int(nested["input_tokens"]))
          output = int(u["output_tokens"]) || int(u["completion_tokens"]) || (nested && int(nested["output_tokens"]))
          reasoning = dig_i(u, "output_tokens_details", "reasoning_tokens") ||
                      dig_i(u, "completion_tokens_details", "reasoning_tokens")
          cached = dig_i(u, "prompt_tokens_details", "cached_tokens") ||
                   int(u["cache_read_input_tokens"]) ||
                   int(u["prompt_cache_hit_tokens"])
          total = int(u["total_tokens"])

          build(input: input, output: output, reasoning: reasoning, cached: cached, total: total)
        end
      end

      def self.build(input: nil, output: nil, reasoning: nil, cached: nil, total: nil)
        total ||= ([input, output].compact.empty? ? nil : [input, output].compact.sum)
        { input: input, output: output, reasoning: reasoning, cached: cached, total: total }
      end

      def self.int(value)
        return nil if value.nil?
        Integer(value)
      rescue ArgumentError, TypeError
        value.respond_to?(:to_i) ? value.to_i : nil
      end

      def self.dig_i(hash, *keys)
        int(hash.is_a?(Hash) ? hash.dig(*keys) : nil)
      end
    end
  end
end
