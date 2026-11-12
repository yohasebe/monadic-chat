require_relative '../../lib/monadic/workbench/chat_output'

# Facade methods for Speech Draft Helper app
# Provides clear interfaces for TextToSpeechHelper functionality

class SpeechDraftHelperOpenAI < MonadicApp
  include OpenAIHelper
  include MonadicHelper
  include MonadicSharedTools::FileOperations

  # list_providers_and_voices is already available from MonadicHelper
  
  # The speech is made in a run folder of the chat's folder and shown on
  # the work screen; without a chat, it goes to the shared folder.
  def text_to_speech(text:, provider: "openai", voice_id: nil, language: "en", instructions: nil, speed: 1.0,
                     session: nil, workbench: nil)
    app_name = (session && session.dig(:parameters, "app_name")) || self.class.name
    job = Monadic::Workbench::ChatOutput.run_folder(session: session, workbench: workbench, app_name: app_name)
    said = super(
      text: text,
      provider: provider,
      voice_id: voice_id || "alloy",
      language: language || "auto",
      instructions: instructions || "",
      speed: speed,
      out_dir: job && job[:path]
    ).to_s
    return said unless job

    name = said[/saved to (\S+\.(?:mp3|wav|ogg|flac|aac))/, 1]
    speech = name && File.join(job[:relative], name)
    unless speech && Monadic::Workspace::Folders.real_path(speech)
      Monadic::Workbench::ChatOutput.drop_if_empty(job)
      return said
    end

    Monadic::Workbench::ChatOutput.said("The speech", speech, shown: Monadic::Workbench::ChatOutput.show(speech, workbench))
  end
end