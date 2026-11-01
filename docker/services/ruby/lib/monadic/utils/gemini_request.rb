# frozen_string_literal: true

module Monadic
  module Utils
    module GeminiRequest
      module_function

      # Google keeps generateContent requests unless store is false.
      def without_storage(body)
        body.merge("store" => false)
      end
    end
  end
end
