# frozen_string_literal: true

require_relative "../utils/timed_transcription"
require_relative "../utils/audio_probe"
require_relative "../utils/language_config"
require_relative "../utils/model_spec"
require_relative "../workspace"

# The timed way of transcribing an audio file (analyze_audio): the same speech
# segments and per-segment transcription as for videos
# (Monadic::Utils::TimedTranscription), on the recording's own clock, with the
# app's own provider. The run is kept in a folder of the chat it belongs to.
module AudioTranscriptionAgent
  TIMED_AUDIO_UNTIMED_NOTE = "(Without times: the Python container predates timed transcripts. " \
                             "Rebuild it with Actions > Build Python Container to get them.)"

  # The model that transcribes the segments. For OpenAI, the chat's STT
  # selection when it can transcribe committed segments in a realtime
  # session, otherwise the default when that can, otherwise none. For the
  # others, the chat's selection when it is theirs, otherwise their default.
  def self.segment_model_for(provider, selected)
    return model_for(provider, selected) unless provider == "openai"

    [model_for("openai", selected), audio_model_for("openai")]
      .compact.find { |m| Monadic::Utils::ModelSpec.supports_segment_transcription?(m) }
  end

  # The session's value for key, or nil. The session of a real chat is a
  # Rack session object, not a Hash, so it is read by key, never by its class.
  def self.session_value(session, key)
    session.respond_to?(:[]) ? session[key] : nil
  end

  # The speech-to-text language chosen for the chat, or nil (detect it).
  def self.chat_language(session)
    runtime = session_value(session, :runtime_settings)
    language = runtime.respond_to?(:[]) ? runtime[:language] : nil
    Monadic::Utils::LanguageConfig.stt_language_code(language)
  end

  # An audio file attached to the chat (by its id), as a path in the shared
  # folder and the chat folder it belongs to. Only an attachment the message
  # being answered allows is taken, while the session is still that chat;
  # an attachment that is not audio is refused.
  def resolve_audio_attachment(attachment_id, session)
    chat_id = AudioTranscriptionAgent.session_value(session, Monadic::Workspace::Chats::SESSION_KEY)
    context = Monadic::Workspace::RequestContext.current
    if context && context.chat_id != chat_id
      raise Monadic::Workspace::Attachments::Unusable.new(:chat_moved_on, "this chat has ended.")
    end

    record = Monadic::Workspace::Attachments.resolve_for_request!(attachment_id: attachment_id.to_s, context: context,
                                                                   session: session)
    raise Monadic::Workspace::Attachments::Unusable.new(:purpose, "attachment #{record[:original_name]} is not an audio file.") unless record[:purpose] == "audio"

    record
  end

  # Returns nil when the timed way does not apply here (the app's provider has
  # no segment transcription, or there is no chat to keep the run in), so the
  # untimed way is used; { fallback: true } when the Python container is too
  # old; otherwise { answer: } (the transcript, or what went wrong).
  # `record` is an attachment of the chat (resolve_audio_attachment), else
  # `audio` names a file in the shared folder.
  def timed_audio_transcript(audio, model, session, record: nil)
    resolved = Monadic::Utils::ProviderCapabilities.resolve(:audio, settings["provider"] || settings[:provider])
    provider = resolved[:provider]
    return nil unless Monadic::Utils::TimedTranscription::PROVIDERS.include?(provider)

    chat_id = AudioTranscriptionAgent.session_value(session, Monadic::Workspace::Chats::SESSION_KEY)
    return nil unless Monadic::Workspace::Ids.valid?(:chat, chat_id)

    segment_model = AudioTranscriptionAgent.segment_model_for(provider, model)
    return nil unless segment_model

    input = Monadic::Utils::SharedPathGuard.command_path((record ? record[:path] : audio).to_s, container: "python")
    return { answer: "Error: #{audio} was not found in the shared folder." } unless input

    Monadic::Utils::AudioProbe.check!(input)
    workspace = if record
                  Monadic::Workspace::Ledger.default.workspace(record[:workspace_id])
                else
                  Monadic::Workspace::Folders.ensure_for_chat!(chat_id, app_name: self.class.name)
                end
    job = Monadic::Workspace::Jobs.create!(workspace[:relative_dir])
    output = Monadic::Utils::SharedPathGuard.command_path(job[:path], container: "python", must_exist: false)
    return { answer: "Error: the run folder is outside the shared folder." } unless output

    result = run_timed_audio(provider: provider, model: segment_model, input: input, job: job, output: output,
                             language: AudioTranscriptionAgent.chat_language(session),
                             cancelled: -> { session[Monadic::Workspace::Chats::SESSION_KEY] != chat_id })
    return { fallback: true } if result[:fallback]

    { answer: timed_audio_answer(result, job) }
  rescue Monadic::Utils::AudioProbe::Rejected => e
    { answer: "Error: #{e.message}" }
  rescue Monadic::Workspace::Jobs::Unavailable, Monadic::Workspace::Ledger::Unreadable => e
    { answer: "Error: #{e.message}" }
  end

  # The run itself, for any caller that has made the run folder (a chat's, or
  # one outside any chat for the MCP server). Sends only to `provider`.
  def run_timed_audio(provider:, model:, input:, job:, output:, language: nil, cancelled: -> { false }, on_attempt: nil)
    Monadic::Utils::TimedTranscription.new(
      provider: provider, model: model, api_key: CONFIG[AUDIO_API_KEYS[provider]],
      api_key_name: AUDIO_API_KEYS[provider], input: input, job: job, output: output,
      timeline: :audio, language: language, cancelled: cancelled, on_attempt: on_attempt,
      transcribe_bytes: ->(wav) { transcribe_audio_bytes(provider, wav, "wav", model, language) }
    ).run
  end

  private

  def timed_audio_answer(result, job)
    parts = ["Transcript (each line starts with the time in the recording of the speech it holds):",
             result[:text].to_s]
    if (subtitles = result[:subtitles])
      named = { vtt: "WebVTT", srt: "SRT" }
      parts << "Subtitles: #{subtitles.map { |kind, address| "#{address} (#{named[kind]})" }.join(', ')}"
    end
    parts << "Saved in the chat's folder: #{job[:relative]}/transcript.json" if result[:saved]
    parts.join("\n\n")
  end
end
