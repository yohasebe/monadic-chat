require 'json'
require 'shellwords'

class ChordAccompanist < MonadicApp
  # Validation script using downloaded abcjs from vendor assets
  # Uses parseOnly method which doesn't require DOM
  def self.abc_validator_js(abcjs_path)
    <<~JS
      const fs = require('fs');
      const vm = require('vm');

      // Load abcjs from vendor assets
      const abcjsPath = '#{abcjs_path}';
      const abcjsCode = fs.readFileSync(abcjsPath, 'utf8');

      // Minimal sandbox for ABCJS (parseOnly doesn't need DOM)
      const sandbox = { window: {}, console: console };
      vm.createContext(sandbox);
      vm.runInContext(abcjsCode, sandbox);

      const ABCJS = sandbox.ABCJS || sandbox.window.ABCJS;

      if (!ABCJS || !ABCJS.parseOnly) {
        console.log(JSON.stringify({ success: false, error: 'ABCJS not loaded' }));
        process.exit(1);
      }

      const code = process.argv[2];
      try {
        // Use parseOnly for validation without DOM rendering
        const result = ABCJS.parseOnly(code);

        if (result && result.length > 0 && result[0].lines && result[0].lines.length > 0) {
          console.log(JSON.stringify({ success: true }));
        } else {
          console.log(JSON.stringify({ success: false, error: 'invalid syntax' }));
        }
      } catch (err) {
        console.log(JSON.stringify({ success: false, error: err.message || 'invalid syntax' }));
      }
    JS
  end

  def validate_abc_syntax(code:)
    sanitized = sanitize_abc(code)

    # Check for music lines without bar lines (common error)
    music_started = false
    sanitized.each_line do |line|
      line = line.strip
      next if line.empty? || line.start_with?('%') || line.start_with?('X:') ||
              line.start_with?('T:') || line.start_with?('C:') || line.start_with?('M:') ||
              line.start_with?('L:') || line.start_with?('Q:') || line.start_with?('K:') ||
              line.start_with?('V:') || line.start_with?('%%')

      music_started = true

      # Check if this is a music line (contains notes or chords) without bar lines
      if line.match?(/["'][A-G]/) && !line.start_with?('|')
        return format_tool_response(
          success: false,
          error: "Music line must start with bar line |: #{line[0..50]}..."
        )
      end
    end

    result = check_with_abcjs(sanitized)

    format_tool_response(result.merge(validated_code: sanitized))
  rescue => e
    format_tool_response(success: false, error: "Validation exception: #{e.message}")
  end

  def analyze_abc_error(code:, error:)
    error_str = error.to_s.downcase
    suggestions = []

    error_patterns = {
      "parse error" => [
        "Check header fields (X:, T:, M:, L:, K:) are in correct order",
        "Ensure all header fields end with newline",
        "Verify bar lines use | not other characters"
      ],
      "syntax error" => [
        "Check note names are valid (A-G with optional modifiers)",
        "Verify rhythm notation (1/4, 1/8, etc.)",
        "Ensure chord symbols are in brackets [CEG]"
      ],
      "invalid" => [
        "Check for special characters in fields",
        "Verify V: (voice) field syntax",
        "Ensure proper spacing around bar lines"
      ],
      "header" => [
        "Headers must appear before the K: field",
        "K: (key) field must be the last header",
        "Required: X: (reference), T: (title), K: (key)"
      ]
    }

    error_patterns.each do |pattern, fixes|
      suggestions.concat(fixes) if error_str.include?(pattern)
    end

    suggestions << "Consult ABC notation reference for proper syntax" if suggestions.empty?

    format_tool_response(
      success: true,
      suggestions: suggestions,
      error_type: error_str
    )
  end

  private

  def sanitize_abc(code)
    cleaned = code.to_s
        .strip
        .gsub(/^```abc\n?/, '')
        .gsub(/^```\n?/, '')
        .gsub(/```$/, '')
        .gsub(/—/, '-')           # Replace em-dash with hyphen
        .gsub(/–/, '-')           # Replace en-dash with hyphen
        .gsub(/[""„]/, '"')       # Replace curly quotes with straight quotes
        .gsub(/['']/, "'")        # Replace curly apostrophes with straight apostrophes
        .gsub(/^\s*\|---+\|[^\n]*$/m, '') # Remove markdown table separator lines like |---|---|
        .gsub(/^\s*[-_=]+\s*$/m, '') # Remove lines containing only decorative characters
        .strip

    # Remove blank lines from music section (after K: header)
    lines = cleaned.split("\n")
    result_lines = []
    in_music_section = false

    lines.each do |line|
      # Once we see K: (key signature), we're in the music section
      in_music_section = true if line =~ /^K:/

      # Skip blank lines in music section, keep all other lines
      if in_music_section && line.strip.empty?
        next
      else
        result_lines << line
      end
    end

    result_lines.join("\n").strip
  end

  def check_with_abcjs(code)
    return { success: false, error: 'Code is empty' } if code.strip.empty?

    # Determine abcjs path based on environment
    abcjs_path = if File.exist?('/monadic/public/vendor/js/abcjs-basic-min.min.js')
                   # Running in container
                   '/monadic/public/vendor/js/abcjs-basic-min.min.js'
                 else
                   # Running on host (rake server:debug)
                   File.expand_path('../../public/vendor/js/abcjs-basic-min.min.js', __dir__)
                 end

    validator_js = self.class.abc_validator_js(abcjs_path)
    escaped_code = Shellwords.escape(code)
    result = `node -e #{Shellwords.escape(validator_js)} #{escaped_code} 2>&1`

    begin
      JSON.parse(result, symbolize_names: true)
    rescue JSON::ParserError
      { success: false, error: 'Validation failed: Could not parse ABC notation' }
    end
  end

  def format_tool_response(hash)
    hash.transform_keys(&:to_s)
  end
end
