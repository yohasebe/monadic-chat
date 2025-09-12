# frozen_string_literal: true

# Lightweight typed exceptions and a small mapper for future use.
# This file is intentionally not wired across the codebase yet to avoid
# behavior changes; it serves as a scaffolding for gradual adoption.

module Monadic
  module Utils
    module ErrorHandlerExt
      class APIError < StandardError; end
      class TimeoutError < APIError; end
      class ParseError < APIError; end

      module_function

      def map_error(e)
        case e
        when HTTP::TimeoutError
          TimeoutError.new("Request timed out")
        when JSON::ParserError
          ParseError.new("Invalid response format")
        else
          APIError.new(e.message)
        end
      end
    end
  end
end

