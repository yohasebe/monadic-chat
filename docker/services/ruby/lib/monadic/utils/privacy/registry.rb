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

        def reset!
          state[:registry] = {}
          state[:audit] = []
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
