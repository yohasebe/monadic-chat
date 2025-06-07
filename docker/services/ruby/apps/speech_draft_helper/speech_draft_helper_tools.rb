# Facade methods for Speech Draft Helper app
# Provides clear interfaces for TextToSpeechHelper functionality

class SpeechDraftHelperOpenAI < MonadicApp
  # list_providers_and_voices is already available from MonadicHelper
  
  # Override text_to_speech to handle parameter mapping
  def text_to_speech(text:, provider: "openai", voice_id: nil, language: "en", instructions: nil)
    # The parent method expects 'voice_id' parameter but in different format
    # Call parent method with proper parameter mapping
    super(
      text: text,
      provider: provider,
      voice_id: voice_id || "alloy",  # Default to "alloy" if not specified
      language: language || "auto",
      instructions: instructions || "",
      speed: 1.0  # Default speed
    )
  end
end