# frozen_string_literal: true

require "set"

module Monadic
  module Utils
    module ProgressiveToolManager
      module_function

      REQUEST_TOOL_REGEX = /request_tool\(\s*["']([\w\-\.:]+)["']\s*\)/i

      def visible_tools(app_name:, session:, app_settings:, default_tools:)
        # Early return if session or app_settings doesn't support Hash-like operations
        # Note: session can be Rack::Session::Abstract::SessionHash, which is Hash-like but not a Hash subclass
        return default_tools unless session.respond_to?(:[]) && session.respond_to?(:[]=) && app_settings.is_a?(Hash)

        metadata = app_settings["progressive_tools"] || app_settings[:progressive_tools]
        return default_tools unless metadata.is_a?(Hash)

        return default_tools unless default_tools.is_a?(Array)

        metadata = deep_symbolize(metadata)
        tools_array = default_tools.dup

        state = ensure_state(session, app_name)
        scan_for_unlock_requests(session, metadata, state)
        apply_event_unlocks(metadata, state)

        allowed_names = Set.new(Array(metadata[:always_visible]).map(&:to_s))
        allowed_names.merge(state[:unlocked])

        # Track names defined in metadata so we only filter those
        defined_names = Set.new(Array(metadata[:all_tool_names]).map(&:to_s))

        filtered = tools_array.select do |tool|
          name = extract_tool_name(tool)
          next true unless name

          name_str = name.to_s
          decision = if defined_names.include?(name_str)
            allowed_names.include?(name_str)
          else
            true
          end

          decision
        end

        filtered
      end

      def capture_tool_requests(session:, app_name:, app_settings:, text:)
        # Note: session can be Rack::Session::Abstract::SessionHash, which is Hash-like but not a Hash subclass
        return unless session.respond_to?(:[]) && session.respond_to?(:[]=) && app_settings.is_a?(Hash)

        metadata = app_settings["progressive_tools"] || app_settings[:progressive_tools]
        return unless metadata.is_a?(Hash)

        content = text.to_s
        return if content.empty?

        metadata = deep_symbolize(metadata)
        state = ensure_state(session, app_name)

        unlockable = extract_unlockable(metadata)
        conditional_names = Set.new(Array(metadata[:conditional]).map do |entry|
          entry.is_a?(Hash) ? deep_symbolize(entry)[:name].to_s : nil
        end.compact)

        content.scan(REQUEST_TOOL_REGEX) do |match|
          request_key = Array(match).first.to_s
          resolved = unlockable[request_key]
          resolved ||= request_key if conditional_names.include?(request_key)
          next if resolved.nil?

          tool_name = resolved.to_s
          state[:unlocked] << tool_name unless state[:unlocked].include?(tool_name)
        end
      end

      def trigger_event(session:, app_name:, event:)
        # Note: session can be Rack::Session::Abstract::SessionHash, which is Hash-like but not a Hash subclass
        return unless session.respond_to?(:[]) && session.respond_to?(:[]=)

        state = ensure_state(session, app_name)
        event_name = event.to_s
        state[:triggered_events] << event_name unless state[:triggered_events].include?(event_name)
      end

      def unlock_tool(session:, app_name:, tool_name:)
        # Note: session can be Rack::Session::Abstract::SessionHash, which is Hash-like but not a Hash subclass
        return unless session.respond_to?(:[]) && session.respond_to?(:[]=)

        state = ensure_state(session, app_name)
        tool = tool_name.to_s
        state[:unlocked] << tool unless state[:unlocked].include?(tool)
      end

      def unlocked?(session:, app_name:, tool_name:)
        # Note: session can be Rack::Session::Abstract::SessionHash, which is Hash-like but not a Hash subclass
        return false unless session.respond_to?(:[]) && session.respond_to?(:[]=)

        state = ensure_state(session, app_name)
        state[:unlocked].include?(tool_name.to_s)
      end

      def ensure_state(session, app_name)
        session[:progressive_tools] ||= {}
        session[:progressive_tools][app_name.to_s] ||= {
          unlocked: [],
          triggered_events: [],
          scanned_count: 0
        }
        state = session[:progressive_tools][app_name.to_s]
        state[:unlocked] ||= []
        state[:triggered_events] ||= []
        state[:scanned_count] ||= 0
        state
      end

      def scan_for_unlock_requests(session, metadata, state)
        messages = Array(session[:messages])
        start_index = state[:scanned_count]
        return if start_index >= messages.length

        unlockable = extract_unlockable(metadata)
        conditional_names = Set.new(Array(metadata[:conditional]).map do |entry|
          entry.is_a?(Hash) ? deep_symbolize(entry)[:name].to_s : nil
        end.compact)

        messages[start_index..-1].each do |msg|
          next unless msg.is_a?(Hash)
          text = msg["text"] || msg[:text]
          next unless text.is_a?(String) && !text.empty?

          text.scan(REQUEST_TOOL_REGEX) do |match|
            request_key = Array(match).first.to_s
            resolved = unlockable[request_key]
            resolved ||= request_key if conditional_names.include?(request_key)
            next unless resolved

            tool_name = resolved.to_s
            unless state[:unlocked].include?(tool_name)
              state[:unlocked] << tool_name
            end
          end
        end

        state[:scanned_count] = messages.length
      end
      private_class_method :scan_for_unlock_requests

      def extract_unlockable(metadata)
        mapping = {}
        Array(metadata[:conditional]).each do |entry|
          next unless entry.is_a?(Hash)
          entry = deep_symbolize(entry)
          tool_name = entry[:name].to_s
          next if tool_name.empty?
          Array(entry[:unlock_conditions]).each do |condition|
            next unless condition.is_a?(Hash)
            condition = deep_symbolize(condition)
            if condition[:tool_request]
              mapping[condition[:tool_request].to_s] = tool_name
            elsif condition[:event]
              mapping[condition[:event].to_s] = tool_name
            end
          end
        end
        mapping
      end
      private_class_method :extract_unlockable

      def apply_event_unlocks(metadata, state)
        triggered = state[:triggered_events]
        return if triggered.nil? || triggered.empty?

        Array(metadata[:conditional]).each do |entry|
          next unless entry.is_a?(Hash)
          entry = deep_symbolize(entry)
          tool_name = entry[:name].to_s
          next if tool_name.empty? || state[:unlocked].include?(tool_name)

          Array(entry[:unlock_conditions]).each do |condition|
            next unless condition.is_a?(Hash)
            condition = deep_symbolize(condition)
            if condition[:event] && triggered.include?(condition[:event].to_s)
              state[:unlocked] << tool_name
              break
            end
          end
        end
      end
      private_class_method :apply_event_unlocks

      def extract_tool_name(tool)
        return tool.name if tool.respond_to?(:name)

        if tool.is_a?(Hash)
          function = tool["function"] || tool[:function]
          return function["name"] if function.is_a?(Hash) && function["name"]
          return function[:name] if function.is_a?(Hash) && function[:name]
          return tool["name"] if tool["name"]
          return tool[:name] if tool[:name]
        end

        nil
      end
      private_class_method :extract_tool_name

      def deep_symbolize(obj)
        case obj
        when Hash
          obj.each_with_object({}) do |(k, v), result|
            key = k.is_a?(String) ? k.to_sym : k
            result[key] = deep_symbolize(v)
          end
        when Array
          obj.map { |v| deep_symbolize(v) }
        else
          obj
        end
      end
      private_class_method :deep_symbolize
    end
  end
end
