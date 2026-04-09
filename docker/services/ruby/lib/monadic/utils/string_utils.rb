# frozen_string_literal: true
require 'csv'
require 'commonmarker'
require_relative 'extra_logger'
require_relative 'markdown_utils'

module StringUtils
  extend self
  # Process TTS dictionary data from CSV format
  def self.process_tts_dictionary(csv_content)
    tts_dict = {}
    return tts_dict if csv_content.nil? || csv_content.empty?
    
    begin
      # Try standard CSV parsing first
      CSV.parse(csv_content, headers: false) do |row|
        # Skip empty rows or rows with missing values
        next if row[0].nil? || row[0].empty? || row[1].nil? || row[1].empty?
        
        # Make sure the data is in UTF-8; otherwise, convert it
        key = row[0].encode("UTF-8", invalid: :replace, undef: :replace, replace: "")
        value = row[1].encode("UTF-8", invalid: :replace, undef: :replace, replace: "")
        
        # Store the original and replacement strings
        tts_dict[key] = value
      end
    rescue StandardError => e
      # Fall back to line-by-line parsing for malformed CSV or other errors
      puts "Error parsing TTS Dictionary, trying line-by-line parsing: #{e.message}"
      
      csv_content.each_line do |line|
        line = line.strip
        next if line.empty? || line.start_with?('#')
        
        # Simple split by first comma
        parts = line.split(',', 2)
        if parts.length == 2
          key = parts[0].strip
          value = parts[1].strip
          
          # Skip empty key/value pairs
          next if key.empty? || value.empty?
          
          # Handle encoding issues
          key = key.encode("UTF-8", invalid: :replace, undef: :replace, replace: "")
          value = value.encode("UTF-8", invalid: :replace, undef: :replace, replace: "")
          
          # Store the dictionary entry
          tts_dict[key] = value
        else
          # Line doesn't have a comma or is otherwise malformed
          puts "Warning: Skipping invalid dictionary entry: #{line}"
        end
      end
    end
    
    tts_dict
  end
  
  # Custom theme wrapper that removes background colors
  class DarkThemeFixer
    # Theme background color mapping
    THEME_BACKGROUNDS = {
      "monokai" => "#272822",
      "monokai_sublime" => "#272822",
      "base16" => "#151515",
      "gruvbox" => "#282828",
      "molokai" => "#1b1d1e",
      "colorful" => "#222222",
      "tulip" => "#2d2d2d",
      "thankful_eyes" => "#2a2a2a"
    }
    
    def initialize(theme, theme_name)
      @theme = theme
      @theme_name = theme_name
    end
    
    def render(scope: "")
      # Get the original CSS
      css = @theme.render(scope: scope)
      
      # Get appropriate background color for this theme (default to a dark gray if unknown)
      bg_color = THEME_BACKGROUNDS[@theme_name] || "#282c34"
      
      # Preserve the theme's background color but make token backgrounds transparent
      css += "\n/* Fix for dark theme backgrounds */\n"
      
      # Only add specific background if we have it in our mapping
      if THEME_BACKGROUNDS.key?(@theme_name)
        css += "\n#{scope} { background-color: #{bg_color} !important; }\n"
      end
      
      # Ensure all tokens and code elements have transparent background while preserving foreground colors
      css += <<~CSS
        #{scope} span, #{scope} pre, #{scope} code, pre#{scope} code { background-color: transparent !important; }
      CSS
      
      css
    end
  end

  module_function

  # language detection using CLD gem
  def detect_language(text)
    CLD.detect_language(text)[:code]
  end

  # Strip Markdown markers and HTML tags for TTS
  # This removes formatting markers that shouldn't be spoken
  def self.strip_markdown_for_tts(text)
    return "" if text.nil?
    return text.to_s unless text.is_a?(String)
    return text if text.empty?

    result = text.dup

    # Remove Markdown bold markers: **text** or __text__
    result = result.gsub(/\*\*(.+?)\*\*/, '\1')
    result = result.gsub(/__(.+?)__/, '\1')

    # Remove Markdown italic markers: *text* or _text_
    # Be careful not to match asterisks in other contexts (e.g., list markers)
    result = result.gsub(/(?<!\*)\*(?!\*)([^\*]+?)\*(?!\*)/, '\1')
    result = result.gsub(/(?<!_)_(?!_)([^_]+?)_(?!_)/, '\1')

    # Remove HTML tags
    result = result.gsub(/<[^>]+>/, '')

    # TTS-specific cleaning
    # Replace full-width spaces (U+3000) with half-width spaces
    result = result.gsub(/　/, ' ')

    # Remove list markers (numbers followed by period or dash at line start)
    result = result.gsub(/^\s*\d+\.\s+/, '')  # Numbered lists: "1. "
    result = result.gsub(/^\s*[-*+]\s+/, '')  # Bullet lists: "- ", "* ", "+ "

    # Remove excessive whitespace
    result = result.gsub(/\s+/, ' ')  # Multiple spaces to single space
    result = result.strip  # Remove leading/trailing whitespace

    result
  end

end
