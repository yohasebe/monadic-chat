# frozen_string_literal: true

require "set"

module Monadic
  module Utils
    # Limits tool calls to the tools offered to the model.
    #
    # Each provider helper records the tool names of the request it is about to
    # send (`record!`), and checks a returned call against them right before it
    # runs the tool (`refusal`). A name that was not offered in the latest
    # request for the app, including any name when nothing was recorded, is
    # refused and its method is not called.
    #
    # The record is kept for the code path that sent the request (fiber-local),
    # not in the session: a helper posts a request, reads its response and runs
    # its tools on one path, so a turn that overlaps it in the same session
    # (another thread) keeps a record of its own. A request sent from inside a
    # tool with a session of its own (the code agents) is recorded under that
    # session and leaves the outer record alone.
    module ToolDispatchGuard
      module_function

      STORE_KEY = :monadic_offered_tool_names
      # Records kept per code path; the oldest is dropped beyond this, and a
      # call checked against a dropped record is refused.
      MAX_RECORDS = 32

      # Tool names in a request's tools, for every provider's shape:
      # {name:}, {function: {name:}}, {type: "function", name:} and Gemini's
      # {function_declarations: [{name:}]}. Entries without a name (native or
      # server tools) are skipped.
      def offered_names(tools)
        list = tools.is_a?(Hash) ? [tools] : Array(tools)
        list.each_with_object(Set.new) do |entry, names|
          next unless entry.is_a?(Hash)

          decls = entry["function_declarations"] || entry[:function_declarations]
          if decls
            Array(decls).each { |d| add_name(names, d) }
          else
            add_name(names, entry)
          end
        end
      end

      def add_name(names, entry)
        return unless entry.is_a?(Hash)

        fn = entry["function"] || entry[:function]
        name = (fn.is_a?(Hash) ? (fn["name"] || fn[:name]) : nil) || entry["name"] || entry[:name]
        name = normalize(name)
        names << name unless name.empty?
      end
      private_class_method :add_name

      def normalize(name)
        name.to_s.strip
      end

      # Record the tools of the request about to be sent for `app` in `session`.
      # A request without tools records an empty list, so a call returned from
      # it is refused.
      def record!(session, app, tools)
        store = (Thread.current[STORE_KEY] ||= {})
        key = key_for(session, app)
        store.delete(key)
        store[key] = offered_names(tools).to_a.sort
        store.shift while store.size > MAX_RECORDS
        store[key]
      end

      # The names recorded on this code path for `app` in `session`, or nil.
      def offered(session, app)
        store = Thread.current[STORE_KEY]
        store && store[key_for(session, app)]
      end

      def allowed?(session, app, name)
        names = offered(session, app)
        !names.nil? && names.include?(normalize(name))
      end

      def key_for(session, app)
        [session.object_id, app.to_s]
      end
      private_class_method :key_for

      # nil when the call may run; otherwise the text to return to the model.
      def refusal(session, app, name)
        return nil if allowed?(session, app, name)

        "❌ Unknown tool: #{normalize(name)}. Only the tools provided in this conversation can be called."
      end
    end
  end
end
