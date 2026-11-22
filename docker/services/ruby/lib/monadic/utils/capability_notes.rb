# frozen_string_literal: true

require "set"
require_relative "provider_capabilities"
require_relative "tts_provider"
require_relative "container_probe"
require_relative "container_dependencies"
require_relative "tool_key_requirements"
require_relative "progressive_tool_manager"
require_relative "secret_references"

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
               "Checked by the app for this message. \"Ready\" means the checks below passed, not that " \
               "the call will succeed; if a call fails, say so."

      # The speech command reads its keys from the config file (its
      # environment has no credentials), so that is where they are looked
      # up here too.
      SPEECH_KEY_SOURCE = ->(name) { SecretReferences.config_value(name) }

      module_function

      def enabled_for?(app_name, env = ENV)
        names = env[FLAG].to_s.split(",").map(&:strip).reject(&:empty?)
        !app_name.to_s.empty? && names.include?(app_name.to_s)
      end

      # The note for the session's app, or nil when it is off or has nothing
      # to say. The container is asked once per user message (request_id);
      # what is unlocked is read anew each time, so the note follows the
      # tools after request_tool.
      def for_session(session, request_id: nil, config: (defined?(CONFIG) ? CONFIG : {}), env: ENV,
                      speech_keys: SPEECH_KEY_SOURCE)
        params = session&.[](:parameters) || {}
        app_name = params["app_name"] || params[:app_name]
        return nil unless enabled_for?(app_name, env)

        app = defined?(APPS) ? APPS[app_name] : nil
        settings = app&.settings
        return nil unless settings.is_a?(Hash)

        build(settings: settings, session: session, app_name: app_name, config: config,
              probe: ->(service) { probe_once(service, request_id) }, speech_keys: speech_keys)
      end

      def probe_once(service, request_id)
        cached = Thread.current[THREAD_KEY]
        return cached[:result] if request_id && cached && cached[:key] == [request_id, service]

        result = with_start(service, ContainerProbe.check(service))
        Thread.current[THREAD_KEY] = { key: [request_id, service], result: result } if request_id
        result
      end

      # A stopped container the app is starting now (for the app the user
      # chose) is reported as starting: the tool cannot use it yet, but it
      # will be there shortly.
      def with_start(service, result)
        return result unless result[:state] == :stopped && ContainerDependencies.starting?(service)

        { state: :starting }
      end

      def build(settings:, session:, app_name:, config:, probe: ->(service) { ContainerProbe.check(service) },
                speech_keys: SPEECH_KEY_SOURCE)
        tools = Array(settings["tools"] || settings[:tools])
        tool_names = tools.map { |t| ToolKeyRequirements.tool_name_of(t).to_s }
        lines = analysis_lines(settings, session, app_name, config, tools) +
                reader_lines(tool_names, probe) +
                speech_lines(tool_names, speech_keys)
        return nil if lines.empty?

        ([HEADER] + lines.map { |line| "- #{line}" }).join("\n")
      end

      # Whether a group is offered comes from the tools this request sends
      # (ProgressiveToolManager.visible_tools), not from the group's
      # declaration; a group neither sent nor unlockable is left out.
      def analysis_lines(settings, session, app_name, config, tools)
        provider = settings["provider"] || settings[:provider]
        app_tool_names = tools.map { |t| ToolKeyRequirements.tool_name_of(t).to_s }
        visible = ProgressiveToolManager.visible_tools(app_name: app_name, session: session, app_settings: settings,
                                                       default_tools: tools)
        visible_names = visible.map { |t| ToolKeyRequirements.tool_name_of(t).to_s }
        metadata = settings["progressive_tools"] || settings[:progressive_tools] || {}
        unlockable_names = Array(metadata["conditional"] || metadata[:conditional]).map { |e| (e["name"] || e[:name]).to_s }
        Array(settings["imported_tool_groups"] || settings[:imported_tool_groups]).filter_map do |group|
          name = (group[:name] || group["name"]).to_sym
          capability, label = ANALYSIS_GROUPS[name]
          next unless capability

          group_tools = MonadicSharedTools::Registry.tools_for(name).map { |t| t.name.to_s } & app_tool_names
          shown = group_tools & visible_names
          offered = if shown.any?
                      "offered as #{shown.join(', ')}"
                    elsif (group_tools & unlockable_names).any?
                      "call request_tool(\"#{name}\") first to get #{(group_tools & unlockable_names).join(', ')}"
                    end
          next unless offered
          resolved = ProviderCapabilities.resolve(capability, provider, config)
          state = if resolved[:error]
                    "not available: #{resolved[:error].delete_prefix('ERROR: ')}. Do not call it; tell the user"
                  else
                    "ready: the provider supports it and its key is set (the file is checked when the tool runs)"
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
                  "ready: the Python container is running (the file is checked when the tool runs)"
                when :stopped
                  "not ready: the Python container is not running. Do not call #{readers.size > 1 ? 'them' : 'it'}; " \
                  "ask the user to paste the text instead"
                when :starting
                  "not ready yet: the Python container is being started. Do not call #{readers.size > 1 ? 'them' : 'it'} " \
                  "now; tell the user it will be ready shortly and to ask again then"
                else
                  "could not be checked (#{result[:reason]}). If a call fails, say that the file could not be read " \
                  "and ask the user to paste the text"
                end
        ["Reading documents with #{names}: #{state}."]
      end

      def speech_lines(tool_names, speech_keys)
        return [] unless tool_names.include?("text_to_speech")

        states = TtsProvider::API_KEYS.map do |provider, key_name|
          TtsProvider.api_key(provider, speech_keys) ? "#{provider} ready" : "#{provider} not available (#{key_name} is not set)"
        end
        ["Speech with text_to_speech: #{states.join('; ')}. The voice list can name providers that are not ready. " \
         "Use only a provider marked ready, and use another provider only when the user chooses it."]
      end

      private_class_method :probe_once, :analysis_lines, :reader_lines, :speech_lines
    end
  end
end
