# frozen_string_literal: true

require_relative 'store'

module Monadic
  module Library
    # Cascade retrieval over the hierarchical Library collections.
    # Strategy:
    #   1. Embed the query once.
    #   2. Search library_summaries (filtered by scope visibility) for the
    #      top-K most relevant conversations.
    #   3. For each candidate conversation, search library_turns scoped to
    #      that conversation_id (and visibility) for the most relevant
    #      turn-level passages.
    #   4. Flatten, re-rank by turn-level score, and return the top_n hits.
    #
    # The cascade is robust to corpora where summary embeddings are weak
    # placeholders (Phase 1a) — the second pass at turn level dominates the
    # ranking. When real LLM-generated summaries land in Phase 1b the same
    # cascade benefits from the upgraded summary signal automatically.
    module Retriever
      module_function

      DEFAULT_TOP_N = 3
      DEFAULT_SUMMARY_TOP_K = 3
      DEFAULT_TURNS_PER_CONV = 2

      # @param query [String] user query
      # @param store [Monadic::Library::Store]
      # @param scope [Symbol] :external (RAG via library_search) or :kb
      # @param top_n [Integer] final number of turn hits returned
      # @param summary_top_k [Integer] convs to consider after summary pass
      # @param turns_per_conv [Integer] turn hits collected per conv
      # @return [Array<Hash>] turn-level hits sorted by score desc, with
      #   keys: text, conversation_id, turn_idx, speaker_role,
      #   start_message_id, score, conversation_title, conversation_source,
      #   conversation_language
      def cascade_search(query,
                         store:,
                         scope: :external,
                         top_n: DEFAULT_TOP_N,
                         summary_top_k: DEFAULT_SUMMARY_TOP_K,
                         turns_per_conv: DEFAULT_TURNS_PER_CONV)
        return [] if query.to_s.strip.empty?

        embeddings = store.embeddings
        query_vec = embeddings.embed_query(query)

        summary_hits = store.search(
          collection: VectorStore::Schema::LIBRARY_SUMMARIES,
          vector: query_vec,
          scope: scope,
          limit: summary_top_k
        )

        return [] if summary_hits.empty?

        all_turn_hits = summary_hits.flat_map do |sh|
          summary_payload = sh['payload'] || {}
          conv_id = summary_payload['conversation_id']
          next [] if conv_id.to_s.empty?

          turn_hits = store.search(
            collection: VectorStore::Schema::LIBRARY_TURNS,
            vector: query_vec,
            scope: scope,
            filter: store.conversation_filter(conv_id),
            limit: turns_per_conv
          )
          turn_hits.map { |th| decorate_turn_hit(th, summary_payload) }
        end

        all_turn_hits
          .sort_by { |h| -(h[:score].to_f) }
          .first(top_n)
      end

      # ─── Internals ─────────────────────────────────────────────────────

      def decorate_turn_hit(hit, summary_payload)
        payload = hit['payload'] || {}
        {
          text: payload['text'].to_s,
          conversation_id: payload['conversation_id'],
          turn_idx: payload['turn_idx'],
          speaker_role: payload['speaker_role'],
          start_message_id: payload['start_message_id'],
          score: hit['score'].to_f,
          conversation_title: summary_payload['title'],
          conversation_source: summary_payload['source'],
          conversation_language: summary_payload['language']
        }
      end
    end
  end
end
