# frozen_string_literal: true

require 'tmpdir'
require 'shellwords'

require_relative 'corpus'

module SttNoiseBenchmark
  # Supplies the clean speech the benchmark degrades.
  #
  # Two sources, in priority order:
  #   1. STT_BENCH_SPEECH_WAV — any 16-bit PCM WAV. Use this for human speech;
  #      the reference run used synthetic audio, which is the single biggest
  #      caveat on its numbers.
  #   2. macOS `say` — synthesises the canonical text so the benchmark is
  #      runnable out of the box on the development machines this project
  #      targets.
  #
  # A trap worth recording: `say` uses the system default voice, which on a
  # Japanese-locale machine is a Japanese voice. English text then comes out
  # as katakana-accented speech and every engine "mis"-transcribes it — an
  # API bug that is really a corpus bug. The voice is therefore pinned.
  module SpeechSource
    DEFAULT_VOICE = 'Samantha'

    # Distinct voices for the babble track. Overlapping speech is the
    # condition that separates omission from fabrication, so it needs several
    # speakers rather than one voice layered on itself.
    BABBLE_VOICES = %w[Daniel Karen Rishi].freeze

    module_function

    def truth_text(dir)
      File.read(File.join(dir, '..', 'data', 'truth.txt')).strip
    end

    # @return [Array(Array<Integer>, Integer)] samples and sample rate
    def load(text: nil, voice: DEFAULT_VOICE)
      supplied = ENV['STT_BENCH_SPEECH_WAV']
      return Corpus.read_wav(supplied) if supplied && !supplied.empty?

      raise unavailable_message unless say_available?

      synthesize(text, voice)
    end

    # @return [Array<Array<Integer>>] one track per babble voice, empty when
    #   `say` is unavailable (the babble conditions are then skipped rather
    #   than silently replaced with white noise)
    def babble_speakers(text: nil)
      return [] unless say_available?

      BABBLE_VOICES.filter_map do |voice|
        samples, = synthesize(text, voice)
        samples
      rescue StandardError
        nil
      end
    end

    def synthesize(text, voice)
      Dir.mktmpdir do |dir|
        aiff = File.join(dir, 'speech.aiff')
        wav = File.join(dir, 'speech.wav')

        system('say', '-v', voice, '-o', aiff, text.to_s, exception: true)
        # afconvert ships with macOS; 16-bit LE PCM mono at 16kHz matches what
        # the REST endpoints expect and upsamples cleanly to 24kHz.
        system('afconvert', '-f', 'WAVE', '-d', 'LEI16@16000', '-c', '1', aiff, wav, exception: true)

        Corpus.read_wav(wav)
      end
    end

    def say_available?
      system('which', 'say', out: File::NULL, err: File::NULL) &&
        system('which', 'afconvert', out: File::NULL, err: File::NULL)
    end

    def unavailable_message
      'No speech source: set STT_BENCH_SPEECH_WAV to a 16-bit PCM WAV, ' \
        'or run on macOS where `say` and `afconvert` are available.'
    end
  end
end
