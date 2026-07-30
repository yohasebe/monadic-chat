# frozen_string_literal: true

require 'json'
require 'time'
require 'fileutils'

require_relative 'wer'
require_relative 'corpus'
require_relative 'engines'

module SttNoiseBenchmark
  # Runs every engine over every noise condition and reports the result.
  #
  # A failing engine is recorded, not raised: one provider being down should
  # leave the rest of the table intact, and "this engine errored" is itself
  # a finding worth keeping in the record.
  class Runner
    def initialize(speech:, speech_rate:, truth:, engines: Engines.default_set, babble_speakers: [],
                   speech_source: nil, log: $stdout)
      @speech = speech
      @speech_rate = speech_rate
      @truth = truth
      @engines = engines
      @babble_speakers = babble_speakers
      @speech_source = speech_source
      @log = log
    end

    def run
      conditions = Corpus.build(@speech, babble_speakers: @babble_speakers)
      started_at = Time.now

      rows = []
      total = @engines.length * conditions.length
      index = 0

      @engines.each do |engine|
        conditions.each do |condition_name, samples|
          index += 1
          # A billed run can take tens of minutes; without per-cell progress an
          # engine stuck in its retry loop is indistinguishable from a hang.
          @log&.puts("[stt_noise_benchmark] #{index}/#{total} #{engine.name} / #{condition_name}")
          row = measure(engine, condition_name, samples)
          @log&.puts("  → #{row[:error] ? row[:error] : format('%<wer>.0f%% WER in %<sec>.1fs', wer: (row[:wer] || 0) * 100, sec: row[:seconds] || 0)}")
          rows << row
        end
      end

      { metadata: metadata(started_at, conditions), truth: @truth, rows: rows }
    end

    # Everything needed to say what was measured and to line two runs up
    # against each other. A results file without this is a number without a
    # subject.
    def metadata(started_at, conditions)
      {
        generated_by: 'stt_noise_benchmark',
        started_at: started_at.utc.iso8601,
        finished_at: Time.now.utc.iso8601,
        noise_seed: Corpus::DEFAULT_NOISE_SEED,
        active_threshold: Corpus::ACTIVE_THRESHOLD,
        speech_source: @speech_source || 'unspecified',
        speech_rate: @speech_rate,
        speech_samples: @speech.length,
        babble_speakers: @babble_speakers.length,
        conditions: conditions.keys,
        engines: @engines.map { |e| { name: e.name, model: e.respond_to?(:model) ? e.model : nil, rate: e.native_rate } }
      }
    end

    def measure(engine, condition_name, samples)
      audio = Corpus.resample(samples, @speech_rate, engine.native_rate)
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      transcript = engine.transcribe(audio, engine.native_rate)
      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started

      analysis = Wer.analyze(@truth, transcript)
      {
        engine: engine.name,
        condition: condition_name,
        transcript: transcript,
        seconds: elapsed.round(2),
        error: nil
      }.merge(analysis)
    rescue StandardError => e
      {
        engine: engine.name,
        condition: condition_name,
        transcript: nil,
        seconds: nil,
        error: "#{e.class}: #{e.message}"
      }
    end

    # ── Reporting ────────────────────────────────────────────────────
    module Report
      module_function

      # WER alone cannot separate an engine that omits from one that invents,
      # so the table carries the hypothesis length next to it. That column is
      # the reason the 2026-07-27 run could say "100% here means no response,
      # not a wrong answer".
      def to_markdown(result)
        conditions = result[:rows].map { |r| r[:condition] }.uniq
        engines = result[:rows].map { |r| r[:engine] }.uniq
        index = result[:rows].each_with_object({}) { |r, acc| acc[[r[:engine], r[:condition]]] = r }

        lines = []
        lines << "| condition | #{engines.join(' | ')} |"
        lines << "|#{'---|' * (engines.length + 1)}"
        conditions.each do |condition|
          cells = engines.map { |engine| format_cell(index[[engine, condition]]) }
          lines << "| #{condition} | #{cells.join(' | ')} |"
        end
        lines << ''
        lines << 'Cells show `WER% (words returned)`. A high WER with 0 words is silence;'
        lines << 'a high WER with many words is fabrication — the distinction that matters.'
        lines.join("\n")
      end

      def format_cell(row)
        return '—' if row.nil?
        return "ERR (#{row[:error].to_s.split(':').first})" if row[:error]

        "#{(row[:wer] * 100).round}% (#{row[:hypothesis_words]}w)"
      end

      def write(result, dir)
        FileUtils.mkdir_p(dir)
        File.write(File.join(dir, 'result.json'), JSON.pretty_generate(result))
        File.write(File.join(dir, 'result.md'), to_markdown(result))
        dir
      end
    end
  end
end
