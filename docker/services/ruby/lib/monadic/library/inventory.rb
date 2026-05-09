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
      # @param app_name [String, nil] when given, only entries scoped to
      #   that app or "Global" are counted (matches what the requesting
      #   app would actually see via library_search). nil counts the full
      #   library — used by KB UI surfaces.
      # @param page_size [Integer] internal scroll batch size
      def summarize(store:, app_name: nil, page_size: 256)
        by_source = Hash.new(0)
        by_content_type = Hash.new(0)
        total = 0

        each_summary_payload(store: store, app_name: app_name, page_size: page_size) do |payload|
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

      def each_summary_payload(store:, app_name: nil, page_size: 256)
        offset = nil
        filter = store.scope_filter(app_name)
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
