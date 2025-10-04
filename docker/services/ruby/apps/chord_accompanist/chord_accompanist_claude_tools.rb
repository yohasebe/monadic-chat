require 'json'
require 'shellwords'

class ChordAccompanistClaude < MonadicApp
  include ClaudeHelper
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

      // Read ABC code from stdin to avoid shell escaping issues
      const code = fs.readFileSync(0, 'utf-8');
      try {
        // Use parseOnly for validation without DOM rendering
        const result = ABCJS.parseOnly(code);

        if (!result || result.length === 0 || !result[0].lines || result[0].lines.length === 0) {
          console.log(JSON.stringify({ success: false, error: 'invalid syntax' }));
          process.exit(0);
        }

        // Check time signature consistency
        const tune = result[0];
        const meter = tune.metaText?.meter;

        if (meter) {
          const meterParts = meter.value.split('/');
          const beatsPerBar = parseInt(meterParts[0]);
          const beatUnit = parseInt(meterParts[1]);
          const expectedDuration = beatsPerBar / beatUnit;

          let barErrors = [];
          let barNumber = 1;

          for (const line of tune.lines) {
            if (line.staff) {
              for (const staff of line.staff) {
                if (staff.voices) {
                  for (const voice of staff.voices) {
                    let currentBarDuration = 0;
                    let currentBarNotes = [];

                    for (const element of voice) {
                      if (element.el_type === 'bar') {
                        // Check accumulated bar duration
                        if (currentBarNotes.length > 0 && Math.abs(currentBarDuration - expectedDuration) > 0.001) {
                          barErrors.push({
                            bar: barNumber,
                            expected: expectedDuration,
                            actual: currentBarDuration,
                            meter: meter.value
                          });
                        }
                        barNumber++;
                        currentBarDuration = 0;
                        currentBarNotes = [];
                      } else if (element.duration !== undefined) {
                        currentBarDuration += element.duration;
                        currentBarNotes.push(element);
                      }
                    }

                    // Check last bar if it has notes
                    if (currentBarNotes.length > 0 && Math.abs(currentBarDuration - expectedDuration) > 0.001) {
                      barErrors.push({
                        bar: barNumber,
                        expected: expectedDuration,
                        actual: currentBarDuration,
                        meter: meter.value
                      });
                    }
                  }
                }
              }
            }
          }

          if (barErrors.length > 0) {
            const errorMsg = barErrors.slice(0, 3).map(e =>
              \`Bar \${e.bar}: expected \${e.expected.toFixed(3)} (\${e.meter}), got \${e.actual.toFixed(3)}\`
            ).join('; ');
            console.log(JSON.stringify({
              success: false,
              error: \`Time signature mismatch: \${errorMsg}\${barErrors.length > 3 ? ' ...' : ''}\`
            }));
            process.exit(0);
          }
        }

        console.log(JSON.stringify({ success: true }));
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

  def validate_chord_progression(chords:, key:)
    # Use Claude for advanced music theory analysis
    prompt = build_chord_validation_prompt(chords, key)

    # Get model from MDSL agents configuration
    model = @context&.dig(:agents, :chord_validator) || @model || "claude-sonnet-4-5-20250929"

    # Call Claude directly for analysis
    result = call_claude_for_validation(prompt, model)

    if result[:success]
      # Parse the analysis from Claude
      analysis = parse_validation_response(result[:content])
      format_tool_response(analysis)
    else
      format_tool_response(
        success: false,
        error: result[:error] || "Chord validation failed"
      )
    end
  rescue => e
    format_tool_response(success: false, error: "Validation exception: #{e.message}")
  end

  def call_claude_for_validation(prompt, model)
    messages = [{ role: "user", content: prompt }]

    response = call_claude(
      messages: messages,
      model: model,
      max_tokens: 4096,
      temperature: 0.0
    )

    if response && response["content"] && response["content"][0]
      {
        success: true,
        content: response["content"][0]["text"]
      }
    else
      {
        success: false,
        error: "No response from Claude"
      }
    end
  rescue => e
    {
      success: false,
      error: "Claude API error: #{e.message}"
    }
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

  def parse_validation_response(response_text)
    # Extract JSON from response (may be wrapped in markdown code blocks)
    json_text = response_text.strip
    json_text = json_text.gsub(/```json\s*/, '').gsub(/```\s*$/, '').strip

    parsed = JSON.parse(json_text, symbolize_names: true)

    {
      success: true,
      valid: parsed[:valid],
      message: parsed[:message],
      explanations: parsed[:explanations] || [],
      invalid_chords: parsed[:invalid_chords] || [],
      suggestions: parsed[:suggestions] || []
    }
  rescue JSON::ParserError => e
    {
      success: false,
      error: "Failed to parse validation response: #{e.message}",
      raw_response: response_text[0..500]
    }
  end

  def build_chord_validation_prompt(chords, key)
    <<~PROMPT
      You are an expert music theorist. Analyze the following chord progression for theoretical correctness.

      Key: #{key}
      Chord Progression: #{chords}

      Analyze each chord and determine if it is theoretically justified. Consider:
      1. Diatonic chords (I, ii, iii, IV, V, vi, vii°)
      2. Secondary dominants (V/II, V/III, V/IV, V/V, V/VI)
      3. Passing diminished chords
      4. Borrowed chords from parallel key (modal interchange)
      5. Tritone substitutions
      6. Tension extensions (9th, 11th, 13th) - check for avoid notes
      7. Modulations to related keys
      8. Voice leading and chord function context

      Return ONLY a JSON object with this exact structure (no markdown, no code blocks):
      {
        "valid": true/false,
        "message": "Overall assessment",
        "explanations": [
          {"position": 1, "chord": "Dm", "function": "Tonic (i in D minor)"},
          ...
        ],
        "invalid_chords": [
          {"position": 3, "chord": "X", "reason": "...", "suggestion": "..."},
          ...
        ],
        "suggestions": ["...", ...]
      }

      If all chords are valid, leave "invalid_chords" as an empty array.
      Be thorough in checking chord construction (e.g., dominant 7th chords must have M3+m7, avoid notes in tensions).
    PROMPT
  end

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

    # Use stdin to pass ABC code to avoid shell escaping issues with multiline strings
    require 'open3'
    validator_js = self.class.abc_validator_js(abcjs_path)
    stdout, stderr, status = Open3.capture3('node', '-e', validator_js, stdin_data: code)
    result = stdout.strip

    begin
      JSON.parse(result, symbolize_names: true)
    rescue JSON::ParserError
      # Include stderr for debugging if JSON parsing fails
      { success: false, error: "Validation failed: #{stderr.empty? ? result[0..200] : stderr[0..200]}" }
    end
  end

  def format_tool_response(hash)
    hash.transform_keys(&:to_s)
  end
end
