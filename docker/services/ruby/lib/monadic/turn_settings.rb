# frozen_string_literal: true

module Monadic
  # The settings one message is answered with: read once from what the
  # message brought, and the same for every request its answer makes (the
  # rounds that send tool results back, a retry) and for the reply shown at
  # its end. The chat's kept parameters are not read for them again, so a
  # setting changed while the answer runs, or left by an earlier message,
  # does not reach it.
  #
  # A field is nil when the message did not say: what that means is each
  # provider's to decide (send a default, or leave the field out).
  #
  # reasoning_effort is the level the message names, as named: which levels
  # a model takes, and what is sent for one it does not, is its provider's.
  # reasoning_content is the switch of a model's thinking where an app or
  # a model has one beside the effort ("enabled", "disabled"); thinking_level
  # is a level an app names for a model that takes levels of its own.
  TurnSettings = Data.define(:model, :show_thinking, :websearch, :reasoning_effort, :reasoning_content,
                             :thinking_level, :temperature,
                             :presence_penalty, :frequency_penalty, :max_tokens, :context_size,
                             :max_input_tokens) do
    # The settings of a message as it is accepted: its own, and for what a
    # chat keeps from message to message (the model, and how much of the
    # chat goes with a message) the chat's where the message leaves it out,
    # as it is at that moment.
    def self.accepted(message, kept)
      message ||= {}
      of(message.merge(%w[model context_size max_input_tokens].to_h do |key|
        [key, message[key].to_s.empty? ? (kept || {})[key] : message[key]]
      end))
    end

    # given: the message as sent (a Hash with String keys), or the
    # parameters a caller made for one request.
    def self.of(given)
      given ||= {}
      new(model: text(given["model"]),
          show_thinking: flag(given["show_thinking"]),
          websearch: flag(given["websearch"]),
          reasoning_effort: text(given["reasoning_effort"]),
          reasoning_content: text(given["reasoning_content"]),
          thinking_level: text(given["thinking_level"]),
          temperature: number(given["temperature"]),
          presence_penalty: number(given["presence_penalty"]),
          frequency_penalty: number(given["frequency_penalty"]),
          max_tokens: count(given["max_tokens"]),
          context_size: count(given["context_size"]),
          max_input_tokens: count(given["max_input_tokens"]))
    end

    # The settings of the request being answered, or those of the given
    # parameters where no message was accepted for it (a caller that makes
    # its own request).
    def self.current(parameters)
      Workspace::RequestContext.current&.settings || of(parameters)
    end

    def self.text(value)
      value.to_s.empty? ? nil : value.to_s.dup.freeze
    end

    # true, false, or nil for anything else.
    def self.flag(value)
      return true if [true, "true"].include?(value)
      return false if [false, "false"].include?(value)

      nil
    end

    # A number, or nil for what is not one ("" and words are not zero).
    def self.number(value)
      n = value.is_a?(Numeric) ? value.to_f : Float(value.to_s.strip, exception: false)
      n&.finite? ? n : nil
    end

    # A whole number above zero, or nil ("1.5" is not one).
    def self.count(value)
      n = value.is_a?(Integer) ? value : Integer(value.to_s.strip, 10, exception: false)
      n&.positive? ? n : nil
    end

    private_class_method :text, :flag, :number, :count
  end
end
