# frozen_string_literal: true

# Encoding utilities for AutoForge
# Based on existing Monadic Chat encoding patterns
module AutoForge
  module Utils
    module EncodingHelper
      extend self

      # Safe UTF-8 encoding with replacement characters
      # @param text [String] Text to encode
      # @param options [Hash] Encoding options
      # @return [String] UTF-8 encoded text
      def safe_encode(text, options = {})
        return "" if text.nil?

        replacement = options[:replace] || "?"
        target_encoding = options[:encoding] || "UTF-8"

        # Convert to string if not already
        text = text.to_s

        # If already in target encoding and valid, return as is
        if text.encoding.name == target_encoding && text.valid_encoding?
          return text
        end

        # Encode with replacement for invalid/undefined characters
        text.encode(target_encoding,
          invalid: :replace,
          undef: :replace,
          replace: replacement
        )
      rescue Encoding::ConverterNotFoundError => e
        # Fall back to force_encoding if converter not found
        text.dup.force_encoding(target_encoding)
      end

      # Force UTF-8 encoding (use with caution)
      # @param text [String] Text to force encode
      # @return [String] Force-encoded text
      def force_utf8(text)
        return "" if text.nil?
        text.dup.force_encoding('UTF-8')
      end

      # Detect encoding of a string
      # @param text [String] Text to analyze
      # @return [Encoding] Detected encoding
      def detect_encoding(text)
        return Encoding::UTF_8 if text.nil? || text.empty?

        # Try to detect using Ruby's built-in detection
        if text.encoding.name != "ASCII-8BIT"
          return text.encoding if text.valid_encoding?
        end

        # Common encodings to try
        encodings = [
          Encoding::UTF_8,
          Encoding::ISO_8859_1,
          Encoding::Windows_1252,
          Encoding::Shift_JIS,
          Encoding::EUC_JP
        ]

        encodings.each do |enc|
          begin
            decoded = text.dup.force_encoding(enc)
            return enc if decoded.valid_encoding?
          rescue
            next
          end
        end

        # Default to binary if nothing works
        Encoding::ASCII_8BIT
      end

      # Normalize line endings to Unix format
      # @param text [String] Text to normalize
      # @return [String] Text with normalized line endings
      def normalize_line_endings(text)
        return "" if text.nil?

        safe_text = safe_encode(text)
        # Convert Windows (CRLF) and old Mac (CR) to Unix (LF)
        safe_text.gsub(/\r\n?/, "\n")
      end

      # Check if text is valid UTF-8
      # @param text [String] Text to check
      # @return [Boolean] True if valid UTF-8
      def valid_utf8?(text)
        return true if text.nil?

        text.encoding == Encoding::UTF_8 && text.valid_encoding?
      rescue
        false
      end

      # Prepare text for file writing
      # @param text [String] Text to prepare
      # @param options [Hash] Options for encoding
      # @return [String] Prepared text
      def prepare_for_file(text, options = {})
        encoded = safe_encode(text, options)
        normalize_line_endings(encoded)
      end
    end
  end
end

# Inline tests
if __FILE__ == $0
  require 'minitest/autorun'

  class EncodingHelperTest < Minitest::Test
    include AutoForge::Utils::EncodingHelper

    def test_safe_encode_with_valid_utf8
      text = "Hello, 世界!"
      result = safe_encode(text)
      assert_equal "Hello, 世界!", result
      assert_equal Encoding::UTF_8, result.encoding
    end

    def test_safe_encode_with_invalid_characters
      text = "Hello\xC3World"  # Invalid UTF-8 sequence
      result = safe_encode(text.dup.force_encoding('UTF-8'))
      assert result.valid_encoding?
    end

    def test_safe_encode_with_nil
      assert_equal "", safe_encode(nil)
    end

    def test_force_utf8
      text = "Hello".encode('ISO-8859-1')
      result = force_utf8(text)
      assert_equal Encoding::UTF_8, result.encoding
    end

    def test_normalize_line_endings
      windows_text = "Line1\r\nLine2\r\nLine3"
      mac_text = "Line1\rLine2\rLine3"
      unix_text = "Line1\nLine2\nLine3"

      assert_equal unix_text, normalize_line_endings(windows_text)
      assert_equal unix_text, normalize_line_endings(mac_text)
      assert_equal unix_text, normalize_line_endings(unix_text)
    end

    def test_valid_utf8
      valid_text = "Valid UTF-8 text"
      invalid_text = "\xFF\xFE Invalid"

      assert valid_utf8?(valid_text)
      refute valid_utf8?(invalid_text.dup.force_encoding('UTF-8'))
    end

    def test_prepare_for_file
      text = "Windows\r\nLine\r\nEndings"
      result = prepare_for_file(text)

      assert_equal "Windows\nLine\nEndings", result
      assert_equal Encoding::UTF_8, result.encoding
    end

    def test_detect_encoding
      utf8_text = "UTF-8 text"
      assert_equal Encoding::UTF_8, detect_encoding(utf8_text)
    end
  end

  puts "\n=== Running EncodingHelper Tests ==="
end