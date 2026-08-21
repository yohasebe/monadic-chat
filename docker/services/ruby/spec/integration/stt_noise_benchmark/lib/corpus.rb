# frozen_string_literal: true

module SttNoiseBenchmark
  # Builds the test corpus: clean speech plus noise mixed at a target SNR.
  #
  # Everything here is deterministic. Noise is generated from a seeded PRNG so
  # two runs on different machines mix the same samples, which is what makes a
  # WER comparison across engines (or across months) mean anything.
  #
  # Audio is handled as 16-bit signed little-endian mono PCM throughout; WAV
  # headers are only added at the boundary because the REST STT endpoints want
  # a container.
  module Corpus
    module_function

    # ── WAV I/O ──────────────────────────────────────────────────────
    # Minimal reader for the canonical 16-bit PCM mono WAV that `say` and
    # ffmpeg produce. Returns [samples(Array<Integer>), sample_rate].
    def read_wav(path)
      bytes = File.binread(path)
      raise ArgumentError, "not a RIFF/WAVE file: #{path}" unless bytes[0, 4] == 'RIFF' && bytes[8, 4] == 'WAVE'

      sample_rate = nil
      channels = nil
      bits = nil
      data = nil

      offset = 12
      while offset + 8 <= bytes.bytesize
        chunk_id = bytes[offset, 4]
        chunk_size = bytes[offset + 4, 4].unpack1('V')
        body = bytes[offset + 8, chunk_size]

        case chunk_id
        when 'fmt '
          channels = body[2, 2].unpack1('v')
          sample_rate = body[4, 4].unpack1('V')
          bits = body[14, 2].unpack1('v')
        when 'data'
          data = body
        end

        # Chunks are word-aligned.
        offset += 8 + chunk_size + (chunk_size.odd? ? 1 : 0)
      end

      raise ArgumentError, "missing fmt/data chunk: #{path}" if data.nil? || sample_rate.nil?
      raise ArgumentError, "expected 16-bit PCM, got #{bits}-bit: #{path}" unless bits == 16

      samples = data.unpack('s<*')
      samples = downmix_to_mono(samples, channels) if channels && channels > 1
      [samples, sample_rate]
    end

    def downmix_to_mono(samples, channels)
      samples.each_slice(channels).map { |frame| frame.sum / channels }
    end

    def write_wav(path, samples, sample_rate)
      File.binwrite(path, wav_bytes(samples, sample_rate))
    end

    def wav_bytes(samples, sample_rate)
      data = samples.pack('s<*')
      byte_rate = sample_rate * 2
      [
        'RIFF', 36 + data.bytesize, 'WAVE',
        'fmt ', 16, 1, 1, sample_rate, byte_rate, 2, 16,
        'data', data.bytesize
      ].pack('a4Va4a4VvvVVvva4V') + data
    end

    # ── Resampling ───────────────────────────────────────────────────
    # Linear interpolation. Good enough for a speech-intelligibility bench and
    # dependency-free; the alternative is shelling out to ffmpeg per condition.
    #
    # Rate matters: OpenAI Realtime rejects anything below 24000, so the same
    # mixed audio has to be offered to each engine at the rate it demands.
    def resample(samples, from_rate, to_rate)
      return samples.dup if from_rate == to_rate

      ratio = from_rate.to_f / to_rate
      out_length = (samples.length / ratio).floor
      Array.new(out_length) do |i|
        pos = i * ratio
        left = pos.floor
        right = [left + 1, samples.length - 1].min
        frac = pos - left
        (samples[left] * (1 - frac) + samples[right] * frac).round
      end
    end

    # ── Noise ────────────────────────────────────────────────────────
    # Seeded so the same condition is byte-identical across runs. The seed is
    # recorded in the results file so a later run can be compared honestly.
    DEFAULT_NOISE_SEED = 20_260_727

    def white_noise(length, seed: DEFAULT_NOISE_SEED)
      rng = Random.new(seed)
      Array.new(length) { ((rng.rand - 0.5) * 2 * 8000).round }
    end

    # Babble: overlapping speech, the condition that separates engines that
    # omit from engines that fabricate. Built by summing shifted copies of the
    # supplied speaker samples, so it needs real speech as raw material.
    def babble_noise(length, speakers, seed: DEFAULT_NOISE_SEED)
      raise ArgumentError, 'babble needs at least one speaker track' if speakers.empty?

      rng = Random.new(seed)
      out = Array.new(length, 0)
      speakers.each do |track|
        next if track.empty?

        offset = rng.rand(track.length)
        length.times do |i|
          out[i] += track[(i + offset) % track.length]
        end
      end
      scale = speakers.length
      out.map { |v| clamp16(v / scale) }
    end

    # ── Mixing ───────────────────────────────────────────────────────
    # Scale `noise` so that the mixture sits at `snr_db` relative to `speech`,
    # then add. Returns clipped 16-bit samples.
    #
    # The speech term is measured over the ACTIVE region only. A clip carries
    # leading and trailing silence, and averaging that in lowers the apparent
    # speech level — the mixture would then be quieter than the label claims,
    # i.e. every engine would be scored on easier audio than the table says.
    # Noise is stationary, so its level is measured over the whole clip.
    def mix_at_snr(speech, noise, snr_db)
      return speech.dup if noise.empty?

      speech_rms = active_rms(speech)
      noise_rms = rms(noise)
      return speech.dup if speech_rms.zero? || noise_rms.zero?

      target_noise_rms = speech_rms / (10.0**(snr_db / 20.0))
      gain = target_noise_rms / noise_rms

      Array.new(speech.length) do |i|
        clamp16((speech[i] + noise[i % noise.length] * gain).round)
      end
    end

    def rms(samples)
      return 0.0 if samples.empty?

      Math.sqrt(samples.sum { |s| s.to_f * s } / samples.length)
    end

    # Fraction of peak amplitude below which a sample counts as silence.
    # Deliberately crude: this only has to exclude the quiet head and tail of
    # a clip, not perform voice activity detection.
    ACTIVE_THRESHOLD = 0.05

    # RMS over samples above the silence floor, falling back to the whole clip
    # when nothing clears it (e.g. a synthetic tone at constant low level).
    def active_rms(samples)
      return 0.0 if samples.empty?

      peak = samples.max_by(&:abs).abs
      return 0.0 if peak.zero?

      floor = peak * ACTIVE_THRESHOLD
      active = samples.select { |s| s.abs >= floor }
      active.empty? ? rms(samples) : rms(active)
    end

    def clamp16(value)
      return 32_767 if value > 32_767
      return -32_768 if value < -32_768

      value
    end

    # ── Conditions ───────────────────────────────────────────────────
    # The grid used for the 2026-07-27 measurements, kept so later runs stay
    # comparable. `nil` snr means clean.
    CONDITIONS = [
      { name: 'clean',        noise: nil,      snr_db: nil },
      { name: 'white_+5dB',   noise: :white,   snr_db: 5 },
      { name: 'white_0dB',    noise: :white,   snr_db: 0 },
      { name: 'babble_+5dB',  noise: :babble,  snr_db: 5 },
      { name: 'babble_0dB',   noise: :babble,  snr_db: 0 }
    ].freeze

    # @param speech [Array<Integer>] clean speech samples
    # @param babble_speakers [Array<Array<Integer>>] tracks for babble noise
    # @return [Hash{String => Array<Integer>}] condition name => samples
    def build(speech, babble_speakers: [])
      CONDITIONS.each_with_object({}) do |condition, acc|
        case condition[:noise]
        when nil
          acc[condition[:name]] = speech.dup
        when :white
          acc[condition[:name]] = mix_at_snr(speech, white_noise(speech.length), condition[:snr_db])
        when :babble
          next if babble_speakers.empty?

          noise = babble_noise(speech.length, babble_speakers)
          acc[condition[:name]] = mix_at_snr(speech, noise, condition[:snr_db])
        end
      end
    end
  end
end
