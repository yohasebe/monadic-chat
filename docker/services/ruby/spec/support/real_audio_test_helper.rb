# frozen_string_literal: true

require 'json'

module RealAudioTestHelper
  # Generate real audio using TTS CLI tool
  def generate_real_audio_file(text, options = {})
    # Validate input
    raise "Text cannot be empty" if text.nil? || text.empty?
    
    provider = options[:provider] || "openai"
    voice = options[:voice] || "alloy"
    speed = options[:speed] || 1.0
    output_format = options[:format] || "mp3"
    
    # Validate provider
    valid_providers = %w[openai openai-tts openai-tts-hd openai-tts-4o elevenlabs gemini webspeech]
    unless valid_providers.include?(provider)
      raise "Invalid provider: #{provider}"
    end
    
    # Generate unique filename
    timestamp = Time.now.to_i
    audio_file = File.join(Dir.home, "monadic", "data", "test_audio_#{timestamp}.#{output_format}")
    
    # Create temporary text file for TTS tool
    text_file = "/tmp/test_text_#{timestamp}.txt"
    
    # Use TTS CLI tool to generate audio (it expects a text file)
    # Properly escape the text for shell
    escaped_text = text.gsub('"', '\\"').gsub("'", "\\'").gsub('$', '\\$').gsub('`', '\\`')
    
    # Write text to a file in the shared volume
    text_filename = "test_text_#{timestamp}.md"
    text_path = File.join(Dir.home, "monadic", "data", text_filename)
    File.write(text_path, text)
    
    # Run locally in development environment
    # Run from the Ruby service directory for proper paths
    script_path = 'scripts/cli_tools/tts_query.rb'
    
    command = <<~BASH
      cd #{File.dirname(__FILE__)}/../.. && \
      ruby -I lib #{script_path} #{text_path} \
        --provider=#{provider} \
        --voice=#{voice} \
        --speed=#{speed} 2>&1
    BASH
    
    result = `#{command}`
    
    # TTS tool outputs audio file with same base name but different extension
    # Look for any audio file with the timestamp
    audio_patterns = ["test_text_#{timestamp}.mp3", "test_text_#{timestamp}.wav", "#{timestamp}.mp3"]
    host_path = nil
    
    audio_patterns.each do |pattern|
      potential_path = File.join(Dir.home, "monadic", "data", pattern)
      if File.exist?(potential_path)
        host_path = potential_path
        break
      end
    end
    
    # Clean up text file
    File.delete(text_path) if File.exist?(text_path)
    
    if host_path && File.exist?(host_path)
      host_path
    else
      raise "Failed to generate audio file: #{result}"
    end
  end
  
  # Convert audio file to WebM format (browser default)
  def convert_to_webm(input_file)
    output_file = input_file.gsub(/\.\w+$/, '.webm')
    
    # Use local ffmpeg
    command = <<~BASH
      ffmpeg -i #{input_file} \
        -c:a libopus -b:a 64k -f webm -y #{output_file} 2>&1
    BASH
    
    result = `#{command}`
    
    if $?.success? && File.exist?(output_file)
      output_file
    else
      raise "Failed to convert to WebM: #{result}"
    end
  end
  
  # Transcribe audio file using STT CLI tool
  def transcribe_audio_file(audio_file, options = {})
    model = options[:model] || CONFIG["STT_MODEL"] || "whisper-1"
    lang = options[:lang] || "en"
    
    # STT tool expects positional arguments: audiofile, outpath, format, lang, model
    output_dir = "/tmp"
    response_format = "json"
    
    # Run locally in development environment
    script_path = 'scripts/cli_tools/stt_query.rb'
    
    command = <<~BASH
      cd #{File.dirname(__FILE__)}/../.. && \
      ruby -I lib #{script_path} \
        #{audio_file} \
        #{output_dir} \
        #{response_format} \
        #{lang} \
        #{model} 2>&1
    BASH
    
    output = `#{command}`
    
    if $?.success?
      # Parse the JSON output to get transcription
      begin
        json_output = JSON.parse(output.lines.last) rescue output
        if json_output.is_a?(Hash) && json_output["text"]
          json_output["text"]
        else
          # If not JSON, just clean up the output
          output.lines.select { |l| !l.include?("Using audio format:") }.join.strip
        end
      rescue
        output.strip
      end
    else
      raise "Failed to transcribe audio: #{output}"
    end
  end
  
  # Alias for backward compatibility
  alias generate_test_audio generate_real_audio_file
  
  # Full TTS -> STT pipeline test
  def test_voice_pipeline(text, options = {})
    audio_file = nil
    webm_file = nil
    
    begin
      # Step 1: Generate audio from text
      audio_file = generate_real_audio_file(text, options)
      puts "Generated audio: #{audio_file}" if ENV['DEBUG']
      
      # Step 2: Convert to WebM if needed (to match browser format)
      if options[:use_webm]
        webm_file = convert_to_webm(audio_file)
        transcribe_file = webm_file
        puts "Converted to WebM: #{webm_file}" if ENV['DEBUG']
      else
        transcribe_file = audio_file
      end
      
      # Step 3: Transcribe the audio
      transcription = transcribe_audio_file(transcribe_file, options)
      puts "Transcription: #{transcription}" if ENV['DEBUG']
      
      {
        success: true,
        original_text: text,
        audio_file: transcribe_file,
        transcription: transcription,
        accuracy: calculate_accuracy(text, transcription)
      }
    rescue => e
      {
        success: false,
        error: e.message,
        original_text: text
      }
    ensure
      # Cleanup test files
      File.delete(audio_file) if audio_file && File.exist?(audio_file) && !ENV['KEEP_TEST_FILES']
      File.delete(webm_file) if webm_file && File.exist?(webm_file) && !ENV['KEEP_TEST_FILES']
    end
  end
  
  # Calculate simple accuracy score
  def calculate_accuracy(original, transcribed)
    return 0.0 if transcribed.nil? || transcribed.empty?
    
    # Normalize both strings for comparison
    original_normalized = original.downcase.gsub(/[^a-z0-9\s\-]/, '').strip
    transcribed_normalized = transcribed.downcase.gsub(/[^a-z0-9\s\-]/, '').strip
    
    # If normalized versions match exactly, perfect accuracy
    if original_normalized == transcribed_normalized
      return 1.0
    end
    
    # Handle number words (e.g., "one" vs "1")
    number_map = {
      "one" => "1", "two" => "2", "three" => "3", "four" => "4", "five" => "5",
      "six" => "6", "seven" => "7", "eight" => "8", "nine" => "9", "ten" => "10"
    }
    
    # Replace number words with digits in both strings
    number_map.each do |word, digit|
      original_normalized.gsub!(/\b#{word}\b/, digit)
      transcribed_normalized.gsub!(/\b#{word}\b/, digit)
    end
    
    # Handle hyphenated numbers (e.g., "1-2-3-4-5" vs "1 2 3 4 5")
    original_with_spaces = original_normalized.gsub('-', ' ')
    transcribed_with_spaces = transcribed_normalized.gsub('-', ' ')
    
    # Check again after number normalization and hyphen handling
    if original_normalized == transcribed_normalized || 
       original_with_spaces == transcribed_with_spaces
      return 1.0
    end
    
    # Calculate word-level accuracy
    original_words = original_normalized.split
    transcribed_words = transcribed_normalized.split
    
    # Use Levenshtein-like approach for partial matches
    matches = 0
    original_words.each_with_index do |word, i|
      if transcribed_words[i] == word
        matches += 1
      elsif transcribed_words.include?(word)
        matches += 0.5  # Partial credit for out-of-order matches
      end
    end
    
    accuracy = matches.to_f / original_words.length
    [accuracy, 1.0].min  # Cap at 1.0
  end
  
  # Send real audio through WebSocket
  def send_real_audio_message(app_name, text_or_audio_file, options = {})
    audio_file = if File.exist?(text_or_audio_file.to_s)
                   text_or_audio_file
                 else
                   # Generate audio from text
                   generate_real_audio_file(text_or_audio_file, options)
                 end
    
    begin
      # Read and encode audio file
      audio_data = File.read(audio_file, mode: "rb")
      audio_base64 = Base64.strict_encode64(audio_data)
      
      # Determine format
      format = File.extname(audio_file).delete('.')
      format = "webm" if format == "webm"
      
      # Send via WebSocket (this would be implemented in e2e_helper)
      message = {
        type: "AUDIO",
        content: audio_base64,
        format: format,
        lang: options[:lang] || "en"
      }
      
      send_websocket_message(app_name, message)
    ensure
      # Cleanup if we generated the file
      if !File.exist?(text_or_audio_file.to_s) && audio_file && File.exist?(audio_file)
        File.delete(audio_file) unless ENV['KEEP_TEST_FILES']
      end
    end
  end
  
  # Test multiple voices and languages
  def test_voice_variations(text, voices: ["alloy", "echo", "fable"], providers: ["openai"])
    results = {}
    
    voices.each do |voice|
      providers.each do |provider|
        key = "#{provider}_#{voice}"
        results[key] = test_voice_pipeline(text, provider: provider, voice: voice)
      end
    end
    
    results
  end
end