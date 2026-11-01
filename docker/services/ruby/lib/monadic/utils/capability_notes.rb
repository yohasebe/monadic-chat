# frozen_string_literal: true

require "set"
require_relative "provider_capabilities"
require_relative "tts_provider"
require_relative "container_probe"
require_relative "tool_key_requirements"

module Monadic
  module Utils
    # A short note for the system prompt on what the app's tools can do now:
    # whether a tool is offered or must be unlocked first, and whether what
    # it needs (a provider that supports it, a key, a running container) is
    # there. Each fact comes from the check the tool itself goes through; the
    # note says nothing the tool would not find out.
    #
    # On only for the apps named in MONADIC_CAPABILITY_NOTES (comma
    # separated), read from the shell's environment, never from the config
    # file. The note is the same text while nothing it reports changes.
    module CapabilityNotes
      FLAG = "MONADIC_CAPABILITY_NOTES"
      THREAD_KEY = :monadic_capability_note

      ANALYSIS_GROUPS = {
        image_analysis: [:image, "Image analysis"],
        audio_transcription: [:audio, "Audio transcription"],
        video_analysis: [:video, "Video analysis"]
      }.freeze

      HEADER = "## What your tools can do now\n" \
               "Checked by the app for this message. \"Ready\" means what the tool needs is there; " \
               "the call itself can still fail, and then you say so."

      module_function

      def enabled_for?(app_name, env = ENV)
        names = env[FLAG].to_s.split(",").map(&:strip).reject(&:empty?)
        !app_name.to_s.empty? && names.include?(app_name.to_s)
      end

      # The note for the session's app, or nil when it is off or has nothing
      # to say. The container is asked once per user message (request_id);
      # what is unlocked is read anew each time, so the note follows the
      # tools after request_tool.
      def for_session(session, request_id: nil, config: (defined?(CONFIG) ? CONFIG : {}), env: ENV)
        params = session&.[](:parameters) || {}
        app_name = params["app_name"] || params[:app_name]
        return nil unless enabled_for?(app_name, env)

        app = defined?(APPS) ? APPS[app_name] : nil
        settings = app&.settings
        return nil unless settings.is_a?(Hash)

        build(settings: settings, session: session, app_name: app_name, config: config,
              probe: ->(service) { probe_once(service, request_id) })
      end

      def probe_once(service, request_id)
        cached = Thread.current[THREAD_KEY]
        return cached[:result] if request_id && cached && cached[:key] == [request_id, service]

        result = ContainerProbe.check(service)
        Thread.current[THREAD_KEY] = { key: [request_id, service], result: result } if request_id
        result
      end

      def build(settings:, session:, app_name:, config:, probe: ->(service) { ContainerProbe.check(service) })
        tool_names = Array(settings["tools"] || settings[:tools]).map { |t| ToolKeyRequirements.tool_name_of(t).to_s }
        lines = analysis_lines(settings, session, app_name, config) +
                reader_lines(tool_names, probe) +
                speech_lines(tool_names, config)
        return nil if lines.empty?

        ([HEADER] + lines.map { |line| "- #{line}" }).join("\n")
      end

      def analysis_lines(settings, session, app_name, config)
        provider = settings["provider"] || settings[:provider]
        unlocked_names = unlocked(session, app_name)
        Array(settings["imported_tool_groups"] || settings[:imported_tool_groups]).filter_map do |group|
          name = (group[:name] || group["name"]).to_sym
          capability, label = ANALYSIS_GROUPS[name]
          next unless capability

          tools = MonadicSharedTools::Registry.tools_for(name).map { |t| t.name.to_s }
          conditional = (group[:visibility] || group["visibility"]).to_s == "conditional"
          offered = if conditional && (tools & unlocked_names).empty?
                      "call request_tool(\"#{name}\") first to get #{tools.join(', ')}"
                    else
                      "offered as #{tools.join(', ')}"
                    end
          resolved = ProviderCapabilities.resolve(capability, provider, config)
          state = if resolved[:error]
                    "not available: #{resolved[:error].delete_prefix('ERROR: ')}. Do not call it; tell the user"
                  else
                    "ready (the file is checked when the tool runs)"
                  end
          "#{label}: #{offered}; #{state}."
        end
      end

      def reader_lines(tool_names, probe)
        return [] unless defined?(MonadicHelper::DOCUMENT_READERS)

        readers = MonadicHelper::DOCUMENT_READERS.select { |tool, r| r[:container] == "python" && tool_names.include?(tool) }
        return [] if readers.empty?

        names = readers.keys.join(", ")
        result = probe.call(:python)
        state = case result[:state]
                when :ready
                  "ready"
                when :stopped
                  "not ready: the Python container is not running. Do not call #{readers.size > 1 ? 'them' : 'it'}; " \
                  "ask the user to paste the text instead"
                else
                  "could not be checked (#{result[:reason]}). If a call fails, say that the file could not be read " \
                  "and ask the user to paste the text"
                end
        ["Reading documents with #{names}: #{state}."]
      end

      def speech_lines(tool_names, config)
        return [] unless tool_names.include?("text_to_speech")

        states = TtsProvider::API_KEYS.map do |provider, key_name|
          TtsProvider.api_key(provider, config) ? "#{provider} ready" : "#{provider} not available (#{key_name} is not set)"
        end
        ["Speech with text_to_speech: #{states.join('; ')}. The voice list can name providers that are not ready. " \
         "Use only a provider marked ready, and use another provider only when the user chooses it."]
      end

      def unlocked(session, app_name)
        state = session&.[](:progressive_tools)&.[](app_name)
        Array(state && (state[:unlocked] || state["unlocked"])).map(&:to_s).sort
      end
      private_class_method :probe_once, :analysis_lines, :reader_lines, :speech_lines, :unlocked
    end
  end
end
