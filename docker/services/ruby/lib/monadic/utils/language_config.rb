# frozen_string_literal: true

module Monadic
  module Utils
    class LanguageConfig
      # Language list based on Whisper API support with native names
      LANGUAGES = {
        "auto" => { english: "Automatic", native: "Automatic" },
        "af" => { english: "Afrikaans", native: "Afrikaans" },
        "ar" => { english: "Arabic", native: "العربية" },
        "hy" => { english: "Armenian", native: "Հայերեն" },
        "az" => { english: "Azerbaijani", native: "Azərbaycan" },
        "be" => { english: "Belarusian", native: "Беларуская" },
        "bs" => { english: "Bosnian", native: "Bosanski" },
        "bg" => { english: "Bulgarian", native: "Български" },
        "ca" => { english: "Catalan", native: "Català" },
        "zh" => { english: "Chinese", native: "中文" },
        "hr" => { english: "Croatian", native: "Hrvatski" },
        "cs" => { english: "Czech", native: "Čeština" },
        "da" => { english: "Danish", native: "Dansk" },
        "nl" => { english: "Dutch", native: "Nederlands" },
        "en" => { english: "English", native: "English" },
        "et" => { english: "Estonian", native: "Eesti" },
        "fi" => { english: "Finnish", native: "Suomi" },
        "fr" => { english: "French", native: "Français" },
        "gl" => { english: "Galician", native: "Galego" },
        "de" => { english: "German", native: "Deutsch" },
        "el" => { english: "Greek", native: "Ελληνικά" },
        "he" => { english: "Hebrew", native: "עברית" },
        "hi" => { english: "Hindi", native: "हिन्दी" },
        "hu" => { english: "Hungarian", native: "Magyar" },
        "is" => { english: "Icelandic", native: "Íslenska" },
        "id" => { english: "Indonesian", native: "Bahasa Indonesia" },
        "it" => { english: "Italian", native: "Italiano" },
        "ja" => { english: "Japanese", native: "日本語" },
        "kn" => { english: "Kannada", native: "ಕನ್ನಡ" },
        "kk" => { english: "Kazakh", native: "Қазақ" },
        "ko" => { english: "Korean", native: "한국어" },
        "lv" => { english: "Latvian", native: "Latviešu" },
        "lt" => { english: "Lithuanian", native: "Lietuvių" },
        "mk" => { english: "Macedonian", native: "Македонски" },
        "ms" => { english: "Malay", native: "Bahasa Melayu" },
        "mr" => { english: "Marathi", native: "मराठी" },
        "mi" => { english: "Māori", native: "Te Reo Māori" },
        "ne" => { english: "Nepali", native: "नेपाली" },
        "no" => { english: "Norwegian", native: "Norsk" },
        "fa" => { english: "Persian", native: "فارسی" },
        "pl" => { english: "Polish", native: "Polski" },
        "pt" => { english: "Portuguese", native: "Português" },
        "ro" => { english: "Romanian", native: "Română" },
        "ru" => { english: "Russian", native: "Русский" },
        "sr" => { english: "Serbian", native: "Српски" },
        "sk" => { english: "Slovak", native: "Slovenčina" },
        "sl" => { english: "Slovenian", native: "Slovenščina" },
        "es" => { english: "Spanish", native: "Español" },
        "sw" => { english: "Swahili", native: "Kiswahili" },
        "sv" => { english: "Swedish", native: "Svenska" },
        "tl" => { english: "Tagalog", native: "Tagalog" },
        "ta" => { english: "Tamil", native: "தமிழ்" },
        "th" => { english: "Thai", native: "ไทย" },
        "tr" => { english: "Turkish", native: "Türkçe" },
        "uk" => { english: "Ukrainian", native: "Українська" },
        "ur" => { english: "Urdu", native: "اردو" },
        "vi" => { english: "Vietnamese", native: "Tiếng Việt" },
        "cy" => { english: "Welsh", native: "Cymraeg" }
      }.freeze

      class << self
        # Get display name for language selector (native with English in parentheses)
        def display_name(code)
          lang = LANGUAGES[code]
          return "Unknown" unless lang
          
          if lang[:native] == lang[:english]
            lang[:native]
          else
            "#{lang[:native]} (#{lang[:english]})"
          end
        end

        # Get list of all languages for selector
        def all_languages
          LANGUAGES.map do |code, names|
            {
              code: code,
              display: display_name(code),
              english: names[:english],
              native: names[:native]
            }
          end
        end

        # Generate system prompt addition for language preference
        def system_prompt_for_language(language_code)
          return "" if language_code.nil? || language_code == "auto"
          
          lang_info = LANGUAGES[language_code]
          return "" unless lang_info
          
          english_name = lang_info[:english]
          
          # Generate appropriate prompt based on language
          <<~PROMPT.strip
            
            IMPORTANT: You MUST respond in #{english_name}. This is a language preference set by the user.
            - Always use #{english_name} for your responses
            - Even if the user writes in a different language, respond in #{english_name} unless explicitly asked to switch
            - Maintain natural, fluent #{english_name} throughout the conversation
          PROMPT
        end

        # Convert language code for STT API (returns nil for "auto")
        def stt_language_code(language_code)
          return nil if language_code.nil? || language_code == "auto"
          language_code
        end

        # Convert language code for TTS API (provider-specific handling)
        def tts_language_code(language_code, provider)
          return "auto" if language_code.nil? || language_code == "auto"
          
          case provider
          when "elevenlabs", "elevenlabs-flash", "elevenlabs-multilingual"
            # ElevenLabs uses full language codes
            language_code
          when "openai"
            # OpenAI TTS uses language parameter
            language_code
          when "gemini"
            # Gemini doesn't use explicit language parameter
            "auto"
          else
            language_code
          end
        end

        # Check if provider supports explicit language specification for TTS
        def tts_supports_language?(provider)
          case provider
          when "elevenlabs", "elevenlabs-flash", "elevenlabs-multilingual", "openai"
            true
          when "gemini"
            false
          else
            false
          end
        end
        
        # Check if a language is RTL (Right-to-Left)
        def rtl_language?(language_code)
          rtl_languages = ["ar", "he", "fa", "ur"]
          rtl_languages.include?(language_code)
        end
        
        # Get text direction for a language
        def text_direction(language_code)
          rtl_language?(language_code) ? "rtl" : "ltr"
        end
      end
    end
  end
end