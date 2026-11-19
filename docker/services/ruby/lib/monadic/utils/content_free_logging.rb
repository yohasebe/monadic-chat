# frozen_string_literal: true

module Monadic
  module Utils
    # Work during which the logs say what happened and never what was sent
    # or came back (the notes kept after a reply ask a provider with the
    # conversation's words). Adapters that log a request body or a
    # provider's error text check active? first.
    module ContentFreeLogging
      KEY = :monadic_content_free_logging

      module_function

      def during
        before = Thread.current[KEY]
        Thread.current[KEY] = true
        yield
      ensure
        Thread.current[KEY] = before
      end

      def active?
        Thread.current[KEY] == true
      end
    end
  end
end
