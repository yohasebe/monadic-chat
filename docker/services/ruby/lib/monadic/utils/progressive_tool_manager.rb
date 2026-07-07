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
          targets = Array(unlockable[request_key]).dup
          targets << request_key if conditional_names.include?(request_key)
          targets.uniq.each do |tool_name|
            state[:unlocked] << tool_name unless state[:unlocked].include?(tool_name)
          end
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

      # Unlock every tool associated with a request key. The key may be a tool
      # group name (unlocks the whole bundle) or an individual conditional tool
      # name (unlocks just that tool). Returns the list of newly unlocked tool
      # names (empty if the key was unknown or everything was already unlocked).
      def unlock_request(session:, app_name:, app_settings:, request_key:)
        return [] unless session.respond_to?(:[]) && session.respond_to?(:[]=)

        metadata = app_settings["progressive_tools"] || app_settings[:progressive_tools] if app_settings.is_a?(Hash)
        return [] unless metadata.is_a?(Hash)

        metadata = deep_symbolize(metadata)
        state = ensure_state(session, app_name)

        mapping = extract_unlockable(metadata)
        conditional_names = Set.new(Array(metadata[:conditional]).map do |entry|
          entry.is_a?(Hash) ? deep_symbolize(entry)[:name].to_s : nil
        end.compact)

        key = request_key.to_s
        targets = Array(mapping[key]).dup
        targets << key if conditional_names.include?(key)

        newly = []
        targets.uniq.each do |tool_name|
          next if state[:unlocked].include?(tool_name)
          state[:unlocked] << tool_name
          newly << tool_name
        end
        newly
      end

      # Execute the request_tool meta-tool for any provider. request_tool has no
      # Ruby method: it exists only to let the model unlock a skill (group or
      # single tool). Reads the requested key from the tool arguments (symbol or
      # string keyed), unlocks it, logs, and returns a confirmation string to feed
      # back as the tool result. Providers call this instead of dispatching
      # request_tool to APPS[app].send.
      def handle_request_tool(session:, app_name:, app_settings:, argument_hash:)
        args = argument_hash.is_a?(Hash) ? argument_hash : {}
        requested = (args[:tool_name] || args["tool_name"] || args[:name] || args["name"]).to_s
        unlocked = unlock_request(
          session: session, app_name: app_name, app_settings: app_settings, request_key: requested
        )
        if defined?(Monadic::Utils::ExtraLogger)
          Monadic::Utils::ExtraLogger.log { "[PTD] request_tool(#{requested.inspect}) -> unlocked #{unlocked.size} tool(s): #{unlocked.inspect}" }
        end
        if unlocked.any?
          "Unlocked: #{unlocked.join(', ')}. These tools are now available — call them as needed."
        elsif requested.empty?
          "No skill name provided. Call request_tool with the name of the skill to unlock."
        else
          "Nothing to unlock for '#{requested}' (already available, or not a known skill)."
        end
      end

      # Build a menu of skills (tool groups) that are still locked for this
      # session, so the model can discover what it may request. Returns a list of
      # human-readable hint strings (one per still-locked group). This is the
      # "progressive disclosure" surface: the model sees names/descriptions of
      # capabilities without their full schemas until it requests them.
      def skill_menu(app_settings:, session:, app_name:)
        return [] unless app_settings.is_a?(Hash)

        metadata = app_settings["progressive_tools"] || app_settings[:progressive_tools]
        return [] unless metadata.is_a?(Hash)

        metadata = deep_symbolize(metadata)
        state = ensure_state(session, app_name)
        unlocked = Set.new(Array(state[:unlocked]).map(&:to_s))

        groups = {}
        Array(metadata[:conditional]).each do |entry|
          next unless entry.is_a?(Hash)
          entry = deep_symbolize(entry)
          name = entry[:name].to_s
          next if name.empty?

          key = nil
          Array(entry[:unlock_conditions]).each do |condition|
            next unless condition.is_a?(Hash)
            condition = deep_symbolize(condition)
            key ||= condition[:tool_request].to_s if condition[:tool_request]
          end
          key ||= name

          group = (groups[key] ||= { hint: nil, names: [] })
          hint = entry[:unlock_hint].to_s
          group[:hint] = hint unless hint.empty?
          group[:names] << name
        end

        lines = []
        groups.each do |key, group|
          next if group[:names].all? { |n| unlocked.include?(n) }
          hint = group[:hint]
          hint = "Call request_tool(\"#{key}\") to unlock." if hint.nil? || hint.empty?
          lines << hint
        end
        lines
      end

      # Return a copy of a provider-formatted tools array in which request_tool's
      # description is augmented with the current skill menu. Non-destructive:
      # the shared app settings tools are never mutated. If nothing is locked (or
      # request_tool is absent), the array is returned unchanged.
      def annotate_request_tool(tools:, app_settings:, session:, app_name:)
        return tools unless tools.is_a?(Array)

        lines = skill_menu(app_settings: app_settings, session: session, app_name: app_name)
        return tools if lines.empty?

        menu = "\n\nAdditional skills are available but currently locked. " \
               "When the conversation calls for one, unlock it by calling this tool " \
               "with the matching skill name. Available skills:\n" +
               lines.map { |line| "- #{line}" }.join("\n")

        tools.map do |tool|
          name = extract_tool_name(tool)
          next tool unless name.to_s == "request_tool"
          annotate_tool_description(tool, menu)
        end
      end

      def annotate_tool_description(tool, suffix)
        return tool unless tool.is_a?(Hash)

        copy = deep_dup(tool)
        if copy["function"].is_a?(Hash)
          copy["function"]["description"] = "#{copy["function"]["description"]}#{suffix}"
        elsif copy[:function].is_a?(Hash)
          copy[:function][:description] = "#{copy[:function][:description]}#{suffix}"
        elsif copy.key?("description")
          copy["description"] = "#{copy["description"]}#{suffix}"
        elsif copy.key?(:description)
          copy[:description] = "#{copy[:description]}#{suffix}"
        end
        copy
      end
      private_class_method :annotate_tool_description

      def deep_dup(obj)
        case obj
        when Hash
          obj.each_with_object({}) { |(k, v), result| result[k] = deep_dup(v) }
        when Array
          obj.map { |v| deep_dup(v) }
        else
          obj
        end
      end
      private_class_method :deep_dup

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
            targets = Array(unlockable[request_key]).dup
            targets << request_key if conditional_names.include?(request_key)
            targets.uniq.each do |tool_name|
              state[:unlocked] << tool_name unless state[:unlocked].include?(tool_name)
            end
          end
        end

        state[:scanned_count] = messages.length
      end
      private_class_method :scan_for_unlock_requests

      # Build a mapping from an unlock key (a tool-group name or event) to the
      # list of tool names it unlocks. A single key (e.g. a group like
      # "web_search_tools") can map to MANY tools, so values are arrays: this is
      # what makes request_tool("<group>") unlock the whole bundle rather than a
      # single tool.
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
            key = condition[:tool_request] || condition[:event]
            next unless key
            key = key.to_s
            mapping[key] ||= []
            mapping[key] << tool_name unless mapping[key].include?(tool_name)
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
