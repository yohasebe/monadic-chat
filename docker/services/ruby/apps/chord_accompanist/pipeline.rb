require 'json'
require 'set'

class ChordAccompanist < MonadicApp
  class Pipeline
    REQUIREMENT_KEYS = %w[tempo time_signature key instrument feel length_bars].freeze
    PIPELINE_MODEL = 'gpt-5'.freeze
    PIPELINE_TEMPERATURE = 0.2
    MAX_LENGTH_BARS = 64
    MIN_LENGTH_BARS = 4

    REQUIREMENTS_SCHEMA = {
      'type' => 'json_schema',
      'json_schema' => {
        'name' => 'chord_accompanist_requirements',
        'strict' => true,
        'schema' => {
          'type' => 'object',
          'properties' => {
            'title' => { 'type' => 'string' },
            'tempo' => { 'type' => 'integer', 'minimum' => 30, 'maximum' => 240 },
            'time_signature' => { 'type' => 'string' },
            'key' => { 'type' => 'string' },
            'instrument' => { 'type' => 'string' },
            'feel' => { 'type' => 'string' },
            'length_bars' => { 'type' => 'integer', 'minimum' => 4, 'maximum' => 64 },
            'style' => { 'type' => 'string' },
            'assumptions' => { 'type' => 'array', 'items' => { 'type' => 'string' } },
            'notes' => { 'type' => 'array', 'items' => { 'type' => 'string' } },
            'reference_tracks' => { 'type' => 'array', 'items' => { 'type' => 'string' } },
            'progression_hint' => { 'type' => 'array', 'items' => { 'type' => 'string' } },
            'tempo_unit' => { 'type' => 'string' }
          },
          'required' => ['tempo', 'time_signature', 'key', 'instrument', 'feel', 'length_bars']
        }
      }
    }.freeze

    PROGRESSION_SCHEMA = {
      'type' => 'json_schema',
      'json_schema' => {
        'name' => 'chord_accompanist_progression',
        'strict' => true,
        'schema' => {
          'type' => 'object',
          'properties' => {
            'sections' => {
              'type' => 'array',
              'minItems' => 1,
              'items' => {
                'type' => 'object',
                'properties' => {
                  'name' => { 'type' => 'string' },
                  'repeat' => { 'type' => 'integer', 'minimum' => 1, 'maximum' => 4 },
                  'bars' => {
                    'type' => 'array',
                    'minItems' => 1,
                    'items' => { 'type' => 'string' }
                  },
                  'notes' => { 'type' => 'array', 'items' => { 'type' => 'string' } }
                },
                'required' => ['name', 'bars']
              }
            },
            'total_bars' => { 'type' => 'integer', 'minimum' => 4, 'maximum' => 128 },
            'assumptions' => { 'type' => 'array', 'items' => { 'type' => 'string' } },
            'warnings' => { 'type' => 'array', 'items' => { 'type' => 'string' } }
          },
          'required' => ['sections', 'total_bars']
        }
      }
    }.freeze

    NOTE_TO_SEMITONE = {
      'C' => 0, 'B#' => 0,
      'C#' => 1, 'Db' => 1,
      'D' => 2,
      'D#' => 3, 'Eb' => 3,
      'E' => 4, 'Fb' => 4,
      'F' => 5, 'E#' => 5,
      'F#' => 6, 'Gb' => 6,
      'G' => 7,
      'G#' => 8, 'Ab' => 8,
      'A' => 9,
      'A#' => 10, 'Bb' => 10,
      'B' => 11, 'Cb' => 11
    }.freeze

    SHARP_NOTE_NAMES = {
      0 => 'C',
      1 => '^C',
      2 => 'D',
      3 => '^D',
      4 => 'E',
      5 => 'F',
      6 => '^F',
      7 => 'G',
      8 => '^G',
      9 => 'A',
      10 => '^A',
      11 => 'B'
    }.freeze

    FLAT_NOTE_NAMES = {
      0 => 'C',
      1 => '_D',
      2 => 'D',
      3 => '_E',
      4 => 'E',
      5 => 'F',
      6 => '_G',
      7 => 'G',
      8 => '_A',
      9 => 'A',
      10 => '_B',
      11 => 'B'
    }.freeze

    REST_SYMBOLS = Set.new(%w[n.c n.c. nc none rest]).freeze

    def initialize(app)
      @app = app
    end

    def run(context:, requirements: nil, progression_hint: nil, reference_tracks: nil, notes: nil)
      context_text = context.to_s.strip
      return failure('Context is required') if context_text.empty?

      normalized_requirements = normalize_requirements_input(requirements)
      normalized_hint = normalize_string_array(progression_hint)
      normalized_references = normalize_string_array(reference_tracks)
      freeform_note = notes.to_s.strip
      freeform_note = nil if freeform_note.empty?

      structured_from_notes = parse_structured_note(freeform_note)

      seed_requirements = merge_requirements(normalized_requirements, structured_from_notes[:requirements])
      if structured_from_notes[:reference_tracks]&.any?
        seed_requirements = merge_requirements(
          seed_requirements,
          { 'reference_tracks' => structured_from_notes[:reference_tracks] }
        )
      end

      initial_notes = structured_from_notes[:notes]
      initial_assumptions = structured_from_notes[:assumptions]

      requirements_result = if complete_requirements?(seed_requirements)
                               {
                                 success: true,
                                 requirements: apply_requirements_defaults(seed_requirements),
                                 notes: initial_notes,
                                 assumptions: initial_assumptions
                               }
                             else
                               gather_requirements(
                                 context_text: context_text,
                                 seed_requirements: seed_requirements,
                                 progression_hint: normalized_hint,
                                 reference_tracks: normalized_references,
                                 freeform_note: freeform_note
                               )
                             end
      return requirements_result unless requirements_result[:success]

      requirements_data = apply_requirements_defaults(requirements_result[:requirements])

      hint_from_notes = structured_from_notes[:progression_hint]
      combined_hint = if hint_from_notes&.any?
                        hint_from_notes
                      elsif normalized_hint.any?
                        normalized_hint
                      else
                        Array(requirements_data['progression_hint'])
                      end

      progression_result = if structured_from_notes[:progression_sections]
                              {
                                success: true,
                                progression: normalize_structured_progression(
                                  structured_from_notes[:progression_sections],
                                  requirements_data['length_bars']
                                ),
                                notes: [],
                                assumptions: initial_assumptions
                              }
                            elsif combined_hint.any?
                              {
                                success: true,
                                progression: progression_from_hint(
                                  combined_hint,
                                  requirements_data['length_bars']
                                ),
                                notes: [],
                                assumptions: initial_assumptions
                              }
                            else
                              build_progression(
                                requirements: requirements_data,
                                context_text: context_text,
                                progression_hint: combined_hint,
                                reference_tracks: normalized_references
                              )
                            end
      return progression_result unless progression_result[:success]

      arrangement_result = build_arrangement(
        requirements: requirements_data,
        progression: progression_result[:progression]
      )
      return arrangement_result unless arrangement_result[:success]

      arrangement_result[:notes] = collect_notes(requirements_result, progression_result, arrangement_result)
      arrangement_result[:assumptions] = collect_assumptions(requirements_result, progression_result, arrangement_result)
      arrangement_result[:requirements] = requirements_data
      arrangement_result[:progression] = progression_result[:progression]
      arrangement_result[:freeform_note] = freeform_note if freeform_note
      arrangement_result
    rescue => e
      failure("Pipeline exception: #{e.class}: #{e.message}")
    end

    private

    def failure(message)
      { success: false, error: message }
    end

    def gather_requirements(context_text:, seed_requirements:, progression_hint:, reference_tracks:, freeform_note:)
      if complete_requirements?(seed_requirements)
        return {
          success: true,
          requirements: seed_requirements,
          notes: ['Using provided requirements'],
          assumptions: Array(seed_requirements['assumptions'])
        }
      end

      payload = {
        context: context_text,
        seed_requirements: seed_requirements,
        progression_hint: progression_hint,
        reference_tracks: reference_tracks,
        notes: freeform_note
      }.compact

      messages = [
        {
          'role' => 'system',
          'content' => <<~PROMPT
            You are RequirementsAgent, responsible for consolidating musical accompaniment requirements.
            Follow the JSON schema strictly.
            - Fill missing tempo, time_signature, key, instrument, feel, and length_bars with sensible defaults.
            - Keep length_bars at or below 32 unless the user explicitly asks for more.
            - Tempo must be an integer BPM.
            - Use ASCII characters only and record assumptions for inferred values.
            - Prefer user-provided values over defaults.
          PROMPT
        },
        {
          'role' => 'user',
          'content' => JSON.pretty_generate(stringify_keys(payload))
        }
      ]

      response = request_json_from_model(
        messages: messages,
        schema: REQUIREMENTS_SCHEMA
      )

      if response[:success]
        data = response[:data].is_a?(Hash) ? stringify_keys(response[:data]) : {}
        notes_from_agent = normalize_string_array(response[:notes]) if response.key?(:notes)
      else
        data = {}
        notes_from_agent = []
      end

      merged = merge_requirements(seed_requirements, data)

      merged['progression_hint'] = normalize_string_array(merged['progression_hint'])
      merged['reference_tracks'] = normalize_string_array(merged['reference_tracks'])
      merged['assumptions'] = normalize_string_array(merged['assumptions'])

      merged['tempo'] = merged['tempo'].to_i if merged['tempo']
      merged['tempo'] = 120 if merged['tempo'].nil? || merged['tempo'] <= 0

      if merged['length_bars']
      merged['length_bars'] = merged['length_bars'].to_i
      merged['length_bars'] = MIN_LENGTH_BARS if merged['length_bars'] < MIN_LENGTH_BARS
      merged['length_bars'] = MAX_LENGTH_BARS if merged['length_bars'] > MAX_LENGTH_BARS
    end

      notes_list = normalize_string_array(data['notes'])
      assumptions = normalize_string_array(data['assumptions'])

      unless response[:success]
        merged = apply_requirements_defaults(merged)
        assumptions << 'Filled missing requirements using local defaults due to upstream failure.'
        notes_list.concat(notes_from_agent || [])
      end

      {
        success: true,
        requirements: merged,
        notes: notes_list,
        assumptions: assumptions
      }
    end

    def build_progression(requirements:, context_text:, progression_hint:, reference_tracks:)
      if requirements['sections']
        normalized = normalize_structured_progression(requirements['sections'], requirements['length_bars'])
        return {
          success: true,
          progression: normalized,
          notes: ['Using sections supplied in requirements'],
          assumptions: Array(requirements['assumptions'])
        }
      end

      payload = {
        context: context_text,
        requirements: requirements,
        progression_hint: progression_hint,
        reference_tracks: reference_tracks
      }.compact

      messages = [
        {
          'role' => 'system',
          'content' => <<~PROMPT
            You are ProgressionAgent. Design a chord progression for accompaniment.
            Follow the JSON schema strictly.
            - Use sections (Verse, Chorus, Bridge, etc.) with ordered bars.
            - Match the requested style, tempo, key, and length.
            - Respect user hints when provided.
            - Use ASCII chord symbols.
            - Record assumptions for inferred structure.
          PROMPT
        },
        {
          'role' => 'user',
          'content' => JSON.pretty_generate(stringify_keys(payload))
        }
      ]

      response = request_json_from_model(
        messages: messages,
        schema: PROGRESSION_SCHEMA
      )

      if response[:success]
        data = response[:data].is_a?(Hash) ? stringify_keys(response[:data]) : {}
        normalized = normalize_structured_progression(data['sections'], requirements['length_bars'])
        normalized['warnings'] = normalize_string_array(data['warnings'])
        assumptions = normalize_string_array(data['assumptions'])
        response_notes = normalized['warnings']
      else
        normalized = fallback_progression(requirements)
        assumptions = ['Applied fallback chord progression due to upstream failure.']
        response_notes = []
      end

      {
        success: true,
        progression: normalized,
        notes: response_notes,
        assumptions: assumptions
      }
    end

    def build_arrangement(requirements:, progression:)
      normalized_progression = if progression.is_a?(Hash) && progression['sections']
                                 progression
                               else
                                 normalize_structured_progression(progression)
                               end

      sections = Array(normalized_progression && normalized_progression['sections'])
      return failure('Progression is empty') if sections.empty?

      time_signature = requirements['time_signature'].to_s.strip
      time_signature = '4/4' if time_signature.empty?
      numerator, denominator = parse_time_signature(time_signature)
      note_length = default_note_length(denominator)
      units = units_per_bar(numerator, denominator, note_length)
      pattern = choose_pattern_type(requirements)

      header_lines = build_header_lines(requirements, time_signature, note_length)
      body_lines, warnings = build_body_lines(sections, pattern: pattern, units: units)

      {
        success: true,
        abc_code: (header_lines + body_lines).join("\n"),
        pattern: pattern.to_s,
        assumptions: warnings,
        notes: normalize_string_array(normalized_progression['warnings']),
        message: "Generated accompaniment with #{pattern} pattern"
      }
    rescue => e
      failure("Arrangement error: #{e.message}")
    end

    def build_header_lines(requirements, time_signature, note_length)
      title = requirements['title'].to_s.strip
      title = derive_title(requirements) if title.empty?

      tempo = requirements['tempo'].to_i
      tempo = 120 if tempo <= 0
      tempo_unit = requirements['tempo_unit'].to_s.strip
      tempo_text = tempo_unit.empty? ? tempo.to_s : "#{tempo} #{tempo_unit}"

      key = requirements['key'].to_s.strip
      key = 'C' if key.empty?

      [
        'X:1',
        "T: #{title}",
        "M: #{time_signature}",
        "L: #{note_length}",
        "Q: #{tempo_text}",
        "K: #{key}",
        'V: Staff1 clef=treble name="Accompaniment"'
      ]
    end

    def derive_title(requirements)
      feel_phrase = requirements['feel'].to_s.strip
      feel_phrase = feel_phrase.split(/\s+/).map(&:capitalize).join(' ')
      instrument_word = requirements['instrument'].to_s.strip.split(/\s+/).first.to_s.capitalize
      base = [feel_phrase, instrument_word].reject(&:empty?).join(' ')
      base = 'Chord Accompaniment' if base.empty?
      base
    end

    def build_body_lines(sections, pattern:, units:)
      lines = []
      warnings = []
      buffer = []

      sections.each do |section|
        name = section['name'].to_s.strip
        lines << "% Section: #{name}" unless name.empty?

        repeat = [section['repeat'].to_i, 1].max
        bars = Array(section['bars'])

        repeat.times do
          bars.each do |symbol|
            render = render_bar(symbol, pattern: pattern, units: units)
            warnings.concat(render[:warnings]) if render[:warnings]
            buffer << render[:bar]

            if buffer.length >= 4
              lines << buffer.join(' ')
              buffer = []
            end
          end
        end
      end

      lines << buffer.join(' ') unless buffer.empty?
      [ensure_final_bar_closed(lines), warnings.uniq]
    end

    def ensure_final_bar_closed(lines)
      return ['|]'] if lines.empty?

      result = lines.dup
      index = result.length - 1
      while index >= 0 && result[index].start_with?('%')
        index -= 1
      end

      if index < 0
        result << '|]'
        return result
      end

      last_line = result[index]
      unless last_line.include?('|]')
        result[index] = last_line.to_s.strip
        result[index] = if result[index].empty?
                          '|]'
                        else
                          "#{result[index]} |]"
                        end
      end

      result
    end

    def render_bar(symbol, pattern:, units:)
      units = units.to_i
      units = 4 if units <= 0

      parsed = parse_chord_symbol(symbol)
      case parsed[:type]
      when :rest
        tokens = Array.new(units, 'z')
        { bar: "| #{tokens.join(' ')}", warnings: [] }
      when :chord
        chord_data = chord_from_parsed(parsed)
        tokens = build_pattern_tokens(chord_data, pattern, units)
        { bar: "| #{tokens.join(' ')}", warnings: chord_data[:warnings] }
      else
        tokens = Array.new(units, 'z')
        warning = "Unknown chord '#{symbol}', substituted with rest"
        { bar: "| #{tokens.join(' ')}", warnings: [warning] }
      end
    end

    def parse_chord_symbol(symbol)
      text = symbol.to_s.strip
      return { type: :rest, original: text } if text.empty? || REST_SYMBOLS.include?(text.downcase)

      base, bass = text.split('/', 2)
      match = base.match(/\A([A-Ga-g])([#♭b♯]?)(.*)\z/)
      return { type: :unknown, original: text } unless match

      letter = match[1].upcase
      accidental = normalize_accidental_char(match[2])
      key = letter + (accidental || '')
      root = NOTE_TO_SEMITONE[key] || NOTE_TO_SEMITONE[letter]
      return { type: :unknown, original: text } if root.nil?

      quality = match[3].to_s.strip
      prefer = accidental == 'b' ? :flat : :sharp
      bass_data = parse_note_token(bass)

      {
        type: :chord,
        root: root,
        prefer: prefer,
        quality: quality,
        bass: bass_data,
        original: text
      }
    end

    def parse_note_token(symbol)
      return nil if symbol.nil?
      token = symbol.to_s.strip
      return nil if token.empty?

      match = token.match(/\A([A-Ga-g])([#♭b♯]?)\z/)
      return nil unless match

      letter = match[1].upcase
      accidental = normalize_accidental_char(match[2])
      key = letter + (accidental || '')
      semitone = NOTE_TO_SEMITONE[key] || NOTE_TO_SEMITONE[letter]
      return nil if semitone.nil?

      {
        semitone: semitone,
        prefer: accidental == 'b' ? :flat : :sharp
      }
    end

    def normalize_accidental_char(char)
      case char
      when '#', '♯'
        '#'
      when 'b', '♭', 'B'
        'b'
      else
        nil
      end
    end

    def chord_from_parsed(parsed)
      intervals = intervals_for_quality(parsed[:quality])
      intervals = [0, 4, 7] if intervals.empty?

      notes = intervals.map do |interval|
        semitone_to_abc(parsed[:root] + interval, prefer: parsed[:prefer])
      end.uniq

      warnings = []
      if notes.empty?
        notes = %w[C E G]
        warnings << "Fallback triad used for #{parsed[:original]}"
      end

      chord_block = "[#{notes.join}]"
      bass_note = if parsed[:bass]
                    semitone_to_abc(parsed[:bass][:semitone], prefer: parsed[:bass][:prefer])
                  else
                    notes.first
                  end

      {
        notes: notes,
        chord_block: chord_block,
        bass: bass_note,
        warnings: warnings
      }
    end

    def build_pattern_tokens(chord_data, pattern, units)
      units = 1 if units <= 0
      chord_block = chord_data[:chord_block]
      bass_note = chord_data[:bass] || chord_block
      notes = chord_data[:notes]

      case pattern
      when :arpeggio
        sequence = ([bass_note] + notes[1..] + [notes.first]).compact
        sequence = [bass_note, chord_block].compact if sequence.empty?
        Array.new(units) { |index| sequence[index % sequence.length] }
      when :pulse
        cycle = [bass_note, chord_block]
        Array.new(units) { |index| cycle[index % cycle.length] }
      else
        Array.new(units, chord_block)
      end
    end

    def intervals_for_quality(quality)
      text = quality.to_s.downcase

      return [0, 3, 6, 10] if text.include?('m7b5') || text.include?('ø')
      return [0, 3, 6, 9] if text.include?('dim7')

      base =
        if text.start_with?('m') && !text.start_with?('maj')
          [0, 3, 7]
        elsif text.include?('dim')
          [0, 3, 6]
        elsif text.include?('aug') || text.include?('+')
          [0, 4, 8]
        elsif text.include?('sus2')
          [0, 2, 7]
        elsif text.include?('sus4') || text.include?('sus')
          [0, 5, 7]
        else
          [0, 4, 7]
        end

      intervals = base.dup
      intervals << 10 if text.include?('7') && !text.include?('maj7') && !text.include?('dim7') && !text.include?('m7b5')
      intervals << 11 if text.include?('maj7') || text.include?('Δ')
      intervals << 9 if text.include?('6') || text.include?('add6')
      intervals << 2 if text.include?('9')

      intervals.map { |value| value % 12 }.uniq
    end

    def semitone_to_abc(value, prefer: :sharp)
      semitone = value.to_i % 12
      table = prefer == :flat ? FLAT_NOTE_NAMES : SHARP_NOTE_NAMES
      table[semitone] || SHARP_NOTE_NAMES[semitone] || 'C'
    end

    def choose_pattern_type(requirements)
      instrument = requirements['instrument'].to_s.downcase
      feel = requirements['feel'].to_s.downcase
      style = requirements['style'].to_s.downcase

      return :arpeggio if feel.include?('ballad') || feel.include?('arpeggio') || instrument.include?('piano')
      return :pulse if feel.include?('swing') || feel.include?('funk') || instrument.include?('guitar') || style.include?('strum')

      :block
    end

    def parse_time_signature(signature)
      parts = signature.to_s.split('/')
      numerator = parts[0].to_i
      denominator = parts[1].to_i
      numerator = 4 if numerator <= 0
      denominator = 4 if denominator <= 0
      [numerator, denominator]
    end

    def default_note_length(denominator)
      return '1/8' if denominator >= 8
      '1/4'
    end

    def units_per_bar(numerator, denominator, note_length)
      l_parts = note_length.to_s.split('/')
      l_den = l_parts.last.to_i
      l_den = 4 if l_den <= 0

      units = (numerator * (l_den.to_f / denominator)).round
      units = numerator if units <= 0
      units
    end

    def normalize_requirements_input(input)
      case input
      when nil
        {}
      when String
        parsed = safe_json_parse(input)
        parsed.is_a?(Hash) ? stringify_keys(parsed) : {}
      when Hash
        stringify_keys(input)
      else
        {}
      end
    rescue
      {}
    end

    def normalize_string_array(values)
      return [] if values.nil?
      Array(values).flatten.compact.map { |value| value.to_s.strip }.reject(&:empty?)
    end

    def complete_requirements?(requirements)
      return false unless requirements.is_a?(Hash)
      REQUIREMENT_KEYS.all? do |key|
        value = requirements[key]
        !(value.nil? || value.to_s.strip.empty?)
      end
    end

    def collect_notes(*results)
      results.flat_map { |r| Array(r[:notes]) }.map { |note| note.to_s.strip }.reject(&:empty?).uniq
    end

    def collect_assumptions(*results)
      results.flat_map { |r| Array(r[:assumptions]) }.map { |item| item.to_s.strip }.reject(&:empty?).uniq
    end

    def merge_requirements(seed, generated)
      base = seed.is_a?(Hash) ? stringify_keys(seed) : {}
      additions = generated.is_a?(Hash) ? stringify_keys(generated) : {}
      additions.each do |key, value|
        next if value.nil?
        if value.respond_to?(:empty?)
          next if value.empty?
        end
        base[key] = value
      end
      base
    end

    def normalize_structured_progression(sections, length_hint = nil)
      normalized_sections = Array(sections).map do |section|
        next unless section.is_a?(Hash)
        section_hash = stringify_keys(section)
        bars = normalize_string_array(section_hash['bars'])
        next if bars.empty?
        {
          'name' => section_hash['name'].to_s.strip,
          'repeat' => [section_hash['repeat'].to_i, 1].max,
          'bars' => bars,
          'notes' => normalize_string_array(section_hash['notes'])
        }
      end.compact

      total_bars = normalized_sections.sum { |section| section['bars'].length * [section['repeat'], 1].max }

      {
        'sections' => normalized_sections,
        'total_bars' => total_bars,
        'length_hint' => length_hint
      }
    end

    def progression_from_hint(chords, length_hint)
      bars = normalize_string_array(chords)
      if length_hint.to_i.positive?
        bars = bars.first(length_hint.to_i)
      end
      bars = %w[C Am F G] if bars.empty?

      normalize_structured_progression(
        [
          {
            'name' => 'Progression',
            'repeat' => 1,
            'bars' => bars,
            'notes' => []
          }
        ],
        length_hint
      )
    end

    def request_json_from_model(messages:, schema:)
      options = {
        'model' => PIPELINE_MODEL,
        'temperature' => PIPELINE_TEMPERATURE,
        'messages' => messages,
        'response_format' => schema
      }

      raw = @app.send_query(options, model: PIPELINE_MODEL)
      parsed = safe_json_parse(raw)

      if parsed.is_a?(Hash)
        { success: true, data: parsed }
      else
        { success: false, error: raw.to_s }
      end
    rescue => e
      { success: false, error: e.message }
    end

    def safe_json_parse(payload)
      return payload if payload.is_a?(Hash)
      return nil if payload.nil?

      text = payload.to_s.strip
      return nil if text.empty?

      if text.start_with?('```')
        text = text.sub(/\A```(?:json)?\s*/i, '').sub(/```\s*\z/, '').strip
      end

      JSON.parse(text)
    rescue JSON::ParserError
      nil
    end

    def stringify_keys(value)
      case value
      when Hash
        value.each_with_object({}) do |(k, v), memo|
          memo[k.to_s] = stringify_keys(v)
        end
      when Array
        value.map { |item| stringify_keys(item) }
      else
        value
      end
    end

    def parse_structured_note(note)
      result = {
        requirements: {},
        progression_hint: [],
        progression_sections: nil,
        reference_tracks: [],
        assumptions: [],
        notes: []
      }
      return result if note.nil? || note.empty?

      text = note.strip

      if (segment = extract_json_segment(text, 'requirements', '{', '}'))
        if (parsed = safe_json_parse(segment))
          parsed = stringify_keys(parsed)
          tempo = parsed.delete('tempo_bpm')
          parsed['tempo'] ||= tempo
          parsed['tempo'] = parsed['tempo'].to_i if parsed['tempo']

          if parsed.key?('instrumentation')
            parsed['instrument'] ||= parsed.delete('instrumentation')
          end

          if parsed.key?('length_bars')
            parsed['length_bars'] = parsed['length_bars'].to_i
          elsif parsed.key?('length')
            length_text = parsed.delete('length').to_s
            if length_text =~ /(\d+)/
              parsed['length_bars'] = Regexp.last_match(1).to_i
            end
          end

          if parsed.key?('time_signature') && parsed['time_signature'].is_a?(Array)
            parsed['time_signature'] = parsed['time_signature'].join('/').to_s
          end

          if parsed.key?('assumptions')
            result[:assumptions] = normalize_string_array(parsed['assumptions'])
            parsed.delete('assumptions')
          end
          result[:requirements] = parsed
        end
      end

      if (hint_segment = extract_json_segment(text, 'progression_hint', '[', ']'))
        if (parsed_hint = safe_json_parse(hint_segment))
          result[:progression_hint] = normalize_string_array(parsed_hint)
        end
      end

      if (progression_segment = extract_json_segment(text, 'progression', '{', '}'))
        if (parsed_prog = safe_json_parse(progression_segment))
          sections = parsed_prog.map do |name, bars|
            next unless bars
            {
              'name' => name.to_s,
              'repeat' => 1,
              'bars' => Array(bars)
            }
          end.compact
          result[:progression_sections] = sections unless sections.empty?
        end
      end

      if (reference_segment = extract_json_segment(text, 'reference_tracks', '[', ']'))
        if (parsed_refs = safe_json_parse(reference_segment))
          result[:reference_tracks] = normalize_string_array(parsed_refs)
        end
      end

      if (sections_segment = extract_json_segment(text, 'progression_sections', '[', ']'))
        if (parsed_sections = safe_json_parse(sections_segment))
          result[:progression_sections] = parsed_sections
        end
      end

      result
    rescue => e
      result[:notes] << "Failed to parse structured notes: #{e.message}"
      result
    end

    def extract_json_segment(text, label, opener, closer)
      label_match = text.match(/#{Regexp.escape(label)}\s*:/i)
      return nil unless label_match

      start_index = text.index(opener, label_match.end(0))
      return nil unless start_index

      depth = 0
      escape = false

      text.chars.each_with_index do |char, idx|
        next if idx < start_index

        if escape
          escape = false
          next
        end

        if char == '\\'
          escape = true
          next
        end

        depth += 1 if char == opener
        depth -= 1 if char == closer

        return text[start_index..idx] if depth.zero?
      end

      nil
    end

    def apply_requirements_defaults(requirements)
      req = requirements.dup
      req['tempo'] = 96 if req['tempo'].nil? || req['tempo'].to_i <= 0
      req['time_signature'] ||= '4/4'
      req['key'] ||= 'C'
      req['instrument'] ||= 'Piano'
      req['feel'] ||= 'even 8th-note pop'
      req['length_bars'] ||= 16
      req
    end

    def fallback_progression(requirements)
      length = requirements['length_bars'].to_i
      length = 16 if length <= 0
      base_cycle = %w[C Am F G]
      bars = Array.new(length) { |idx| base_cycle[idx % base_cycle.length] }
      {
        'sections' => [
          {
            'name' => 'Fallback',
            'repeat' => 1,
            'bars' => bars
          }
        ],
        'total_bars' => bars.length,
        'length_hint' => requirements['length_bars']
      }
    end
  end
end
