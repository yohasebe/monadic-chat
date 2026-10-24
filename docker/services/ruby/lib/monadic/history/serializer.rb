# frozen_string_literal: true

require 'json'
require_relative '../utils/secret_redactor'

module Monadic
  module History
    # What of a chat is written to the history: the fields listed here, and
    # nothing else. A field that is not listed (a newer one, an image's data,
    # the rendered HTML, thinking, a tool's raw record) is left out. What is
    # kept passes through the secret redactor, which removes known keys and
    # 1Password references; the list is the main guard, the redactor a second.
    module Serializer
      FORMAT_VERSION = 1
      MESSAGE_FIELDS = %w[mid role text app_name lang request_id timestamp model].freeze
      ATTACHMENT_FIELDS = %w[attachment_id purpose].freeze
      PARAMETER_FIELDS = %w[
        app_name model reasoning_effort context_size initial_prompt
        websearch math conversation_language
      ].freeze
      HEADING_LIMIT = 80

      module_function

      # The payload for a chat, or nil when there is nothing to keep yet
      # (no user message).
      def payload(session)
        messages = Array(value_of(session, :messages)).filter_map { |m| message(m) }
        return nil unless messages.any? { |m| m['role'] == 'user' && !m['text'].to_s.strip.empty? }

        data = {
          'format_version' => FORMAT_VERSION,
          'messages' => messages,
          'parameters' => pick(value_of(session, :parameters), PARAMETER_FIELDS),
          'session_context' => session_context(session)
        }.compact
        Monadic::Utils::SecretRedactor.redact_deep(data)
      end

      # A one-line heading from the first user message with words in it, and
      # one from the most recent, each cut to HEADING_LIMIT characters.
      def headings(payload)
        texts = payload['messages'].filter_map do |m|
          next unless m['role'] == 'user'

          line = m['text'].to_s.gsub(/```.*?```/m, ' ').gsub(/\s+/, ' ').strip
          line unless line.empty?
        end
        first = texts.first
        recent = texts.length > 1 ? texts.last : nil
        [cut(first), cut(recent)]
      end

      def message(raw)
        return nil unless raw.is_a?(Hash)

        out = pick(raw, MESSAGE_FIELDS)
        return nil unless %w[user assistant system].include?(out['role'])

        refs = Array(raw['attachments'] || raw[:attachments]).filter_map do |ref|
          picked = pick(ref, ATTACHMENT_FIELDS)
          picked unless picked.empty?
        end
        out['attachments'] = refs unless refs.empty?
        out
      end

      def session_context(session)
        state = value_of(session, :monadic_state)
        return nil unless state.is_a?(Hash)

        context = state[:conversation_context] || state['conversation_context']
        context.is_a?(Hash) && !context.empty? ? JSON.parse(JSON.generate(context)) : nil
      end

      def pick(hash, fields)
        return {} unless hash.is_a?(Hash)

        fields.each_with_object({}) do |field, out|
          value = hash.key?(field) ? hash[field] : hash[field.to_sym]
          out[field] = value if [String, Integer, Float, TrueClass, FalseClass].any? { |t| value.is_a?(t) }
        end
      end

      def value_of(session, key)
        session[key] || session[key.to_s]
      end

      def cut(text)
        return nil if text.nil?

        text.length > HEADING_LIMIT ? "#{text[0, HEADING_LIMIT - 1]}…" : text
      end
    end
  end
end
