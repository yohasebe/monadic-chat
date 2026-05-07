# frozen_string_literal: true

require 'json'
require 'securerandom'
require 'time'

require_relative 'turn_segmenter'

module Monadic
  module Library
    # Orchestrates the hierarchical embedding pipeline. Takes a
    # monadic-conversation v1 hash, segments it into turns, embeds
    # everything via the embeddings client, and upserts into the
    # Library Qdrant collections through Store.
    #
    # Levels:
    #   :summary  — one point per conversation (placeholder embedding
    #               from the first 1-2 turns; replace with LLM-generated
    #               summaries in a future phase without breaking the
    #               vector + metadata flow)
    #   :turns    — main RAG retrieval unit consumed by library_search
    #
    # Per-message embeddings are reserved for a future phase and not
    # produced here.
    module Hierarchical
      module_function

      DEFAULT_LEVELS = %i[summary turns].freeze

      # @param conversation [Hash] monadic-conversation v1 conformant
      # @param store [Monadic::Library::Store]
      # @param scope_app [String] app class name (e.g. "ChatOpenAI") or
      #   the Store::SCOPE_GLOBAL sentinel ("Global"). The literal value
      #   is stored on every produced point and used by library_search to
      #   decide whether the requesting app may see the conversation.
      # @param levels [Array<Symbol>] subset of DEFAULT_LEVELS
      # @return [Hash] counts of upserted points per level
      def ingest(conversation,
                 store:,
                 scope_app: Store::SCOPE_GLOBAL,
                 levels: DEFAULT_LEVELS)
        validate_inputs!(conversation, scope_app)
        embeddings = store.embeddings
        conv_id = conversation['conversation_id']
        turns = TurnSegmenter.segment(conversation)
        counts = { summary: 0, turns: 0 }

        if levels.include?(:summary)
          counts[:summary] = upsert_summary(conversation, turns, conv_id, scope_app, store, embeddings)
        end

        if levels.include?(:turns) && !turns.empty?
          counts[:turns] = upsert_turns(turns, conv_id, scope_app, store, embeddings)
        end

        counts
      end

      # ─── Private helpers ───────────────────────────────────────────────

      def validate_inputs!(conversation, scope_app)
        raise ArgumentError, 'conversation must be a Hash' unless conversation.is_a?(Hash)
        raise ArgumentError, "missing conversation_id" if conversation['conversation_id'].to_s.empty?
        if scope_app.to_s.strip.empty?
          raise ArgumentError, "scope_app must be a non-empty string (an app class name or 'Global')"
        end
      end

      # Placeholder summary: concatenate the first ~1500 chars of the
      # first two turns. A future revision will swap this for an
      # LLM-generated summary; the vector + metadata flow is intentionally
      # the same so the swap stays internal.
      def build_placeholder_summary_text(conversation, turns)
        if turns.any?
          (turns.first(2).map { |t| t[:text] }.join("\n\n"))[0, 1500].strip
        else
          (conversation.dig('conversation_metadata', 'title') ||
           conversation['conversation_id']).to_s
        end
      end

      # Soft cap on the JSON byte size of the original messages array we
      # carry inside the summary payload. Above this we skip embedding the
      # raw messages — the conversation can still be retrieved/searched
      # via turns, just not displayed verbatim in the Viewer modal.
      SUMMARY_MESSAGES_MAX_BYTES = 1_000_000

      def summary_payload(conversation, turns, scope_app)
        meta = conversation['conversation_metadata'] || {}
        messages = conversation['messages'] || []
        participants = conversation['participants'] || []
        messages_payload, messages_skipped_reason = embed_messages_or_skip(conversation['conversation_id'], messages)

        payload = {
          'conversation_id' => conversation['conversation_id'],
          'scope_app' => scope_app.to_s,
          # content_type is forward-compatible: future importers (PDF /
          # Office / Markdown / code files) write 'document' / 'pdf' /
          # 'code' here so the Browse modal can show a per-type icon.
          'content_type' => (meta['content_type'] || 'conversation').to_s,
          'source' => meta['source'],
          'language' => meta['language'],
          'title' => meta['title'],
          'license' => meta['license'],
          'topics' => meta['topics'],
          'duration_seconds' => meta['duration_seconds'],
          'participants_count' => participants.size,
          'messages_count' => messages.size,
          'turns_count' => turns.size,
          'created_at' => Time.now.utc.iso8601,
          # Verbatim messages + participants for the Conversation Viewer
          # modal. Other consumers (search, retrieval) ignore these
          # fields. Skipped silently when over SUMMARY_MESSAGES_MAX_BYTES.
          'messages' => messages_payload,
          'participants' => participants,
          'messages_skipped_reason' => messages_skipped_reason
        }
        payload.compact
      end

      # Returns [messages_or_nil, reason_or_nil]. When the JSON-encoded
      # messages exceed the soft cap, we drop them and stash a reason so
      # the Viewer can show an actionable explanation.
      def embed_messages_or_skip(conv_id, messages)
        return [nil, nil] if messages.empty?
        size = JSON.generate(messages).bytesize
        if size > SUMMARY_MESSAGES_MAX_BYTES
          if defined?(Monadic::Utils::ExtraLogger)
            Monadic::Utils::ExtraLogger.log {
              "[Library] messages payload for conversation #{conv_id} is " \
                "#{size} bytes (limit #{SUMMARY_MESSAGES_MAX_BYTES}); Viewer will mark it as truncated"
            }
          end
          return [nil, "exceeded #{SUMMARY_MESSAGES_MAX_BYTES} bytes (#{size})"]
        end
        [messages, nil]
      end

      def upsert_summary(conversation, turns, conv_id, scope_app, store, embeddings)
        text = build_placeholder_summary_text(conversation, turns)
        return 0 if text.strip.empty?
        vector = embeddings.embed_passages([text]).first
        store.upsert_points(
          collection: VectorStore::Schema::LIBRARY_SUMMARIES,
          points: [{
            id: SecureRandom.uuid,
            vector: { 'content' => vector },
            payload: summary_payload(conversation, turns, scope_app)
          }]
        )
        1
      end

      def turn_payload(turn, conv_id, scope_app)
        {
          'conversation_id' => conv_id,
          'scope_app' => scope_app.to_s,
          'turn_idx' => turn[:turn_idx],
          'speaker_id' => turn[:speaker_id],
          'speaker_role' => turn[:speaker_role],
          'text' => turn[:text],
          'start_message_id' => turn[:start_message_id],
          'end_message_id' => turn[:end_message_id],
          'start_offset_seconds' => turn[:start_offset_seconds],
          'end_offset_seconds' => turn[:end_offset_seconds],
          'message_count' => turn[:message_count]
        }.compact
      end

      def upsert_turns(turns, conv_id, scope_app, store, embeddings)
        vectors = embeddings.embed_passages(turns.map { |t| t[:text] })
        points = turns.each_with_index.map do |turn, idx|
          {
            id: SecureRandom.uuid,
            vector: { 'content' => vectors[idx] },
            payload: turn_payload(turn, conv_id, scope_app)
          }
        end
        store.upsert_points(
          collection: VectorStore::Schema::LIBRARY_TURNS,
          points: points
        )
        turns.size
      end
    end
  end
end
