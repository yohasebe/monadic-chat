# frozen_string_literal: true

module Monadic
  module Library
    # Slice the messages array of a monadic-conversation into "turns".
    #
    # Rules:
    #   - Monologue (single distinct speaker) → each message is its own turn.
    #     Important for talk transcripts where preserving segment granularity
    #     matters for trajectory analysis.
    #   - Multi-speaker → consecutive messages by the same speaker collapse
    #     into a single turn; a speaker change opens a new turn.
    #
    # Returns an array of Hash:
    #   {
    #     turn_idx:           Integer (0-based),
    #     speaker_id:         String,
    #     speaker_role:       String (broad enum),
    #     text:               String (joined with "\n"),
    #     start_message_id:   String,
    #     end_message_id:     String,
    #     start_offset_seconds: Float | nil,
    #     end_offset_seconds:   Float | nil,
    #     message_count:      Integer
    #   }
    module TurnSegmenter
      module_function

      def segment(conversation)
        messages = conversation['messages'] || []
        participants = conversation['participants'] || []
        return [] if messages.empty?

        if monologue?(messages)
          # Preserve per-message granularity for trajectory analysis.
          messages.each_with_index.map { |m, idx| build_turn(idx, [m], participants) }
        else
          collapse_consecutive(messages, participants)
        end
      end

      # ─── Internals ─────────────────────────────────────────────────────

      def monologue?(messages)
        messages.map { |m| m.dig('speaker', 'id') }.uniq.size == 1
      end

      def collapse_consecutive(messages, participants)
        turns = []
        bucket = []
        current_speaker = nil

        messages.each do |m|
          sid = m.dig('speaker', 'id')
          if sid == current_speaker
            bucket << m
          else
            turns << build_turn(turns.size, bucket, participants) unless bucket.empty?
            current_speaker = sid
            bucket = [m]
          end
        end
        turns << build_turn(turns.size, bucket, participants) unless bucket.empty?
        turns
      end

      def build_turn(idx, messages, participants)
        speaker_id = messages.first.dig('speaker', 'id')
        speaker = participants.find { |p| p['id'] == speaker_id }
        first_timing = messages.first['timing'] || {}
        last_timing = messages.last['timing'] || {}
        start_offset = first_timing['offset_seconds']
        last_offset = last_timing['offset_seconds']
        last_duration = last_timing['duration_seconds']
        end_offset = if last_offset && last_duration
                       last_offset.to_f + last_duration.to_f
                     else
                       last_offset
                     end

        {
          turn_idx: idx,
          speaker_id: speaker_id,
          speaker_role: speaker&.dig('role') || 'other',
          text: messages.map { |m| m['text'].to_s }.join("\n").strip,
          start_message_id: messages.first['id'],
          end_message_id: messages.last['id'],
          start_offset_seconds: start_offset,
          end_offset_seconds: end_offset,
          message_count: messages.size
        }
      end
    end
  end
end
