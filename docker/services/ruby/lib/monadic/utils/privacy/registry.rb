# frozen_string_literal: true

module Monadic
  module Utils
    module Privacy
      # Per-session privacy state held in memory only. Lives at
      # session[:monadic_state][:privacy]; never persisted to PStore (RD-1).
      class Registry
        SESSION_KEY = :privacy

        def initialize(session)
          @session = session
        end

        def state
          @session[:monadic_state] ||= {}
          @session[:monadic_state][SESSION_KEY] ||= {
            registry: {},
            audit: []
          }
        end

        def registry
          state[:registry]
        end

        def audit
          state[:audit]
        end

        def merge!(new_registry)
          state[:registry].merge!(new_registry)
        end

        def append_audit(op, **payload)
          state[:audit] << { ts: Time.now.to_i, op: op, **payload }
        end

        def count
          state[:registry].size
        end

        # Strings the user marked in this chat ({ text:, type: }), masked
        # wherever they occur from then on. A string marked again with
        # another type takes the new type.
        def terms
          state[:terms] ||= []
        end

        MAX_TERMS = 200 # as many as the Privacy container takes

        class TooManyTerms < StandardError; end

        # All or nothing: when the words would be more than MAX_TERMS, none
        # is added and TooManyTerms is raised.
        def add_terms!(new_terms)
          list = terms.dup
          Array(new_terms).each do |term|
            text = term[:text] || term['text']
            type = term[:type] || term['type']
            next if text.to_s.empty?

            list.reject! { |t| (t[:text] || t['text']) == text }
            list << { text: text, type: type }
          end
          raise TooManyTerms, "a chat can have at most #{MAX_TERMS} marked words" if list.size > MAX_TERMS

          state[:terms] = list
        end

        def reset!
          state[:registry] = {}
          state[:audit] = []
          state[:terms] = []
        end

        # Strip privacy state from a session payload before persistence to
        # PStore. Use at every save point (RD-1: registry must not touch disk).
        def self.strip_for_persist(session_payload)
          return session_payload unless session_payload.is_a?(Hash)
          payload = session_payload.dup
          if payload[:monadic_state].is_a?(Hash)
            payload[:monadic_state] = payload[:monadic_state].reject { |k, _| k == SESSION_KEY }
          end
          payload
        end
      end
    end
  end
end
