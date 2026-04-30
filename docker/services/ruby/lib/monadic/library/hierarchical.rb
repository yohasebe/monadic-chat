# frozen_string_literal: true

require 'securerandom'
require 'time'

require_relative 'turn_segmenter'
require_relative 'trajectory'

module Monadic
  module Library
    # Orchestrates the hierarchical embedding pipeline. Takes a
    # monadic-conversation v1 hash, segments it into turns, builds
    # trajectory windows, embeds everything via the embeddings client, and
    # upserts into the four Library Qdrant collections through Store.
    #
    # Levels:
    #   :summary     — one point per conversation (Phase 1a uses a
    #                  placeholder embedding from the first 1-2 turns;
    #                  Phase 1b will swap in real LLM-generated summaries)
    #   :turns       — Level 2, the main RAG retrieval unit
    #   :trajectory  — Level T, sliding-window discourse state
    #
    # Level 1 (per-message) is reserved for Phase 1b+ and not produced
    # here.
    module Hierarchical
      module_function

      DEFAULT_LEVELS = %i[summary turns trajectory].freeze
      DEFAULT_WINDOW_SIZE = Trajectory::DEFAULT_WINDOW_SIZE

      # @param conversation [Hash] monadic-conversation v1 conformant
      # @param store [Monadic::Library::Store]
      # @param visibility ['personal' | 'shareable']
      # @param levels [Array<Symbol>] subset of DEFAULT_LEVELS
      # @param window_size [Integer] trajectory window size in turns
      # @return [Hash] counts of upserted points per level
      def ingest(conversation,
                 store:,
                 visibility: Store::VISIBILITY_PERSONAL,
                 levels: DEFAULT_LEVELS,
                 window_size: DEFAULT_WINDOW_SIZE)
        validate_inputs!(conversation, visibility)
        embeddings = store.embeddings
        conv_id = conversation['conversation_id']
        turns = TurnSegmenter.segment(conversation)
        counts = { summary: 0, turns: 0, trajectory: 0 }

        if levels.include?(:summary)
          counts[:summary] = upsert_summary(conversation, turns, conv_id, visibility, store, embeddings)
        end

        if levels.include?(:turns) && !turns.empty?
          counts[:turns] = upsert_turns(turns, conv_id, visibility, store, embeddings)
        end

        if levels.include?(:trajectory) && !turns.empty?
          counts[:trajectory] = upsert_trajectory(turns, conv_id, visibility, store, embeddings, window_size)
        end

        counts
      end

      # ─── Private helpers ───────────────────────────────────────────────

      def validate_inputs!(conversation, visibility)
        raise ArgumentError, 'conversation must be a Hash' unless conversation.is_a?(Hash)
        raise ArgumentError, "missing conversation_id" if conversation['conversation_id'].to_s.empty?
        unless Store::VALID_VISIBILITIES.include?(visibility.to_s)
          raise ArgumentError,
            "visibility must be one of #{Store::VALID_VISIBILITIES.inspect}, got #{visibility.inspect}"
        end
      end

      # Phase 1a placeholder summary: concatenate the first ~1500 chars of
      # the conversation. Phase 1b will replace this with a real
      # LLM-generated summary, but the vector + metadata flow stays the
      # same so the swap is internal.
      def build_placeholder_summary_text(conversation, turns)
        if turns.any?
          (turns.first(2).map { |t| t[:text] }.join("\n\n"))[0, 1500].strip
        else
          (conversation.dig('conversation_metadata', 'title') ||
           conversation['conversation_id']).to_s
        end
      end

      def summary_payload(conversation, turns, visibility)
        meta = conversation['conversation_metadata'] || {}
        payload = {
          'conversation_id' => conversation['conversation_id'],
          'visibility' => visibility.to_s,
          'source' => meta['source'],
          'language' => meta['language'],
          'title' => meta['title'],
          'license' => meta['license'],
          'topics' => meta['topics'],
          'duration_seconds' => meta['duration_seconds'],
          'participants_count' => (conversation['participants'] || []).size,
          'messages_count' => (conversation['messages'] || []).size,
          'turns_count' => turns.size,
          'created_at' => Time.now.utc.iso8601
        }
        payload.compact
      end

      def upsert_summary(conversation, turns, conv_id, visibility, store, embeddings)
        text = build_placeholder_summary_text(conversation, turns)
        return 0 if text.strip.empty?
        vector = embeddings.embed_passages([text]).first
        store.upsert_points(
          collection: VectorStore::Schema::LIBRARY_SUMMARIES,
          points: [{
            id: SecureRandom.uuid,
            vector: { 'content' => vector },
            payload: summary_payload(conversation, turns, visibility)
          }]
        )
        1
      end

      def turn_payload(turn, conv_id, visibility)
        {
          'conversation_id' => conv_id,
          'visibility' => visibility.to_s,
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

      def upsert_turns(turns, conv_id, visibility, store, embeddings)
        vectors = embeddings.embed_passages(turns.map { |t| t[:text] })
        points = turns.each_with_index.map do |turn, idx|
          {
            id: SecureRandom.uuid,
            vector: { 'content' => vectors[idx] },
            payload: turn_payload(turn, conv_id, visibility)
          }
        end
        store.upsert_points(
          collection: VectorStore::Schema::LIBRARY_TURNS,
          points: points
        )
        turns.size
      end

      def trajectory_payload(window, conv_id, visibility)
        {
          'conversation_id' => conv_id,
          'visibility' => visibility.to_s,
          'turn_idx' => window[:turn_idx],
          'start_turn_idx' => window[:start_turn_idx],
          'end_turn_idx' => window[:end_turn_idx],
          'window_size' => window[:window_size]
        }
      end

      def upsert_trajectory(turns, conv_id, visibility, store, embeddings, window_size)
        windows = Trajectory.build_windows(turns, window_size: window_size)
        vectors = embeddings.embed_passages(windows.map { |w| w[:text] })
        points = windows.each_with_index.map do |window, idx|
          {
            id: SecureRandom.uuid,
            vector: { 'content' => vectors[idx] },
            payload: trajectory_payload(window, conv_id, visibility)
          }
        end
        store.upsert_points(
          collection: VectorStore::Schema::LIBRARY_TRAJECTORY,
          points: points
        )
        windows.size
      end
    end
  end
end
