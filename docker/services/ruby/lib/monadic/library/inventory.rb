# frozen_string_literal: true

require_relative 'store'

module Monadic
  module Library
    # Inventory aggregates the Library summaries collection by `source` and
    # `content_type` so the SystemPromptInjector can surface a category-aware
    # "what's in your Knowledge Base" block when the per-session RAG toggle
    # is on. Counts are intentionally data-driven — there is no hard-coded
    # category list — so any new source or content_type that lands on disk
    # shows up in the prompt automatically.
    #
    # Computation cost: one scroll over `library_summaries` (payload-only,
    # no vectors) per conversation start. For typical individual users this
    # is well under a hundred entries; if libraries grow large we can layer
    # a TTL cache here without changing callers.
    module Inventory
      module_function

      # Build a structured summary of what's currently in the Library.
      #
      # @param store [Monadic::Library::Store]
      # @param scope [Symbol] :kb (personal + shareable, what RAG sees) or
      #   :external (shareable-only). Defaults to :kb because the prompt
      #   block is meant to describe everything the user has consented to
      #   expose via the per-session toggle.
      # @param page_size [Integer] internal scroll batch size
      # @return [Hash] {
      #   total: Integer,
      #   by_source: {String => Integer},          # e.g. "monadic-chat" => 1
      #   by_content_type: {String => Integer}     # e.g. "conversation" => 11
      # }
      def summarize(store:, scope: :kb, page_size: 256)
        by_source = Hash.new(0)
        by_content_type = Hash.new(0)
        total = 0

        each_summary_payload(store: store, scope: scope, page_size: page_size) do |payload|
          total += 1
          source = payload['source'].to_s
          source = '(unknown)' if source.empty?
          by_source[source] += 1

          content_type = payload['content_type'].to_s
          content_type = 'conversation' if content_type.empty?
          by_content_type[content_type] += 1
        end

        {
          total: total,
          by_source: by_source.sort.to_h,
          by_content_type: by_content_type.sort.to_h
        }
      end

      # Iterate every summary payload in the requested scope. Yields the
      # parsed payload Hash for each point. Uses scroll pagination so
      # libraries larger than `page_size` still complete in one logical
      # call.
      def each_summary_payload(store:, scope: :kb, page_size: 256)
        offset = nil
        filter = store.visibility_filter(scope)
        loop do
          page = store.scroll(
            collection: VectorStore::Schema::LIBRARY_SUMMARIES,
            filter: filter,
            limit: page_size,
            offset: offset
          )
          Array(page[:points]).each do |point|
            payload = point['payload'] || {}
            yield payload
          end
          offset = page[:next]
          break if offset.nil?
        end
      end
    end
  end
end
