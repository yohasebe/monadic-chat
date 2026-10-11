require_relative '../workspace'
require_relative '../utils/shared_path_guard'

module MonadicHelper
  def analyze_image(message: "", image_path: "", model: nil, detail: nil)
    message = message.gsub(/"/, '\"')
    image_analysis_agent(message: message, image_path: image_path, detail: detail)
  end

  # In a chat, with a provider that transcribes speech segments, each line
  # of the transcript carries the time in the recording (no file size limit
  # beyond the length limit); otherwise the whole file is transcribed at once.
  # attachment_id: an audio file the user attached to this chat (preferred);
  # audio: a file in the shared folder.
  def analyze_audio(audio: "", attachment_id: nil, model: nil, session: nil)
    # Models sometimes pass the attachment id as the file name.
    if attachment_id.to_s.empty? && Monadic::Workspace::Ids.valid?(:attachment, audio.to_s.strip)
      attachment_id = audio.to_s.strip
    end
    return "Error: attachment_id or audio is required." if attachment_id.to_s.empty? && audio.to_s.strip.empty?

    record = nil
    unless attachment_id.to_s.empty?
      begin
        record = resolve_audio_attachment(attachment_id, session)
      rescue Monadic::Workspace::Attachments::Unusable => e
        return "Error: #{e.message}"
      end
      audio = record[:path]
    end

    # Get STT model from Web UI settings (stored in session by websocket handler)
    stt_model = settings["stt_model"] || settings[:stt_model] || model
    timed = timed_audio_transcript(audio, stt_model, session, record: record)
    return timed[:answer] if timed && !timed[:fallback]

    # The whole-file way sends the file as it is, which takes fewer formats
    # than the timed way decodes (not AAC or Opus).
    ext = File.extname(audio.to_s).downcase
    unless Monadic::Utils::SharedPathGuard::AUDIO_EXTENSIONS.include?(ext)
      return "Error: #{ext} files are transcribed only with times: in a chat, with OpenAI, Google Gemini or " \
             "xAI Grok, and with the Python container of this version (Actions > Build Python Container)."
    end

    result = audio_transcription_agent(audio_path: audio, model: stt_model,
                                       lang_code: AudioTranscriptionAgent.chat_language(session))
    timed ? "#{result}\n\n#{AudioTranscriptionAgent::TIMED_AUDIO_UNTIMED_NOTE}" : result
  end
end
