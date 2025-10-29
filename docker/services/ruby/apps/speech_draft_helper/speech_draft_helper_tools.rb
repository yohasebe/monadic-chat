# Facade methods for Speech Draft Helper app
# Provides clear interfaces for TextToSpeechHelper functionality

class SpeechDraftHelperOpenAI < MonadicApp
  include OpenAIHelper
  include MonadicHelper
  include MonadicSharedTools::FileOperations

  # list_providers_and_voices is already available from MonadicHelper
  
  # Override text_to_speech to handle parameter mapping
  def text_to_speech(text:, provider: "openai", voice_id: nil, language: "en", instructions: nil, speed: 1.0)
    # The parent method expects 'voice_id' parameter but in different format
    # Call parent method with proper parameter mapping
    super(
      text: text,
      provider: provider,
      voice_id: voice_id || "alloy",  # Default to "alloy" if not specified
      language: language || "auto",
      instructions: instructions || "",
      speed: speed  # Pass through the speed parameter
    )
  end
end