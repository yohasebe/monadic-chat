# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require_relative 'lib/corpus'

# Runs unconditionally: pure DSP, no network. If the mixing is wrong every
# published WER number is wrong, so the SNR the mixer claims to produce is
# pinned by measuring it back out of the mixture.
RSpec.describe SttNoiseBenchmark::Corpus do
  # A 440Hz tone stands in for speech: deterministic, and its RMS is known
  # well enough to verify the mixer without shipping an audio fixture.
  def tone(length: 24_000, freq: 440, rate: 24_000, amplitude: 8000)
    Array.new(length) { |i| (Math.sin(2 * Math::PI * freq * i / rate) * amplitude).round }
  end

  describe 'WAV round-trip' do
    it 'reads back what it wrote' do
      samples = tone(length: 1000)

      Dir.mktmpdir do |dir|
        path = File.join(dir, 'probe.wav')
        described_class.write_wav(path, samples, 24_000)
        read_samples, rate = described_class.read_wav(path)

        expect(rate).to eq(24_000)
        expect(read_samples).to eq(samples)
      end
    end

    it 'rejects a file that is not RIFF/WAVE' do
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'bogus.wav')
        File.binwrite(path, 'not audio at all')
        expect { described_class.read_wav(path) }.to raise_error(ArgumentError, /RIFF/)
      end
    end
  end

  describe '.resample' do
    it 'returns a copy when the rate is unchanged' do
      samples = tone(length: 100)
      expect(described_class.resample(samples, 24_000, 24_000)).to eq(samples)
    end

    it 'halves the sample count when halving the rate' do
      samples = tone(length: 1000)
      expect(described_class.resample(samples, 24_000, 12_000).length).to eq(500)
    end

    # OpenAI Realtime rejects anything below 24000, so upsampling 16k material
    # is a required step, not an optimisation.
    it 'upsamples 16k to 24k' do
      samples = tone(length: 1600, rate: 16_000)
      expect(described_class.resample(samples, 16_000, 24_000).length).to eq(2400)
    end

    it 'preserves the signal shape well enough to stay recognisable' do
      original = tone(length: 2400)
      round_trip = described_class.resample(
        described_class.resample(original, 24_000, 48_000), 48_000, 24_000
      )
      # Upsample then downsample should land close to where it started.
      deviation = original.take(2000).each_with_index.sum { |v, i| (v - round_trip[i]).abs }
      expect(deviation / 2000.0).to be < 200
    end
  end

  describe '.white_noise' do
    it 'is deterministic for a given seed' do
      expect(described_class.white_noise(500, seed: 42))
        .to eq(described_class.white_noise(500, seed: 42))
    end

    it 'differs between seeds' do
      expect(described_class.white_noise(500, seed: 1))
        .not_to eq(described_class.white_noise(500, seed: 2))
    end
  end

  describe '.babble_noise' do
    it 'is deterministic for a given seed and speaker set' do
      speakers = [tone(length: 5000, freq: 300), tone(length: 5000, freq: 500)]
      a = described_class.babble_noise(2000, speakers, seed: 7)
      b = described_class.babble_noise(2000, speakers, seed: 7)
      expect(a).to eq(b)
    end

    it 'stays within 16-bit range' do
      speakers = Array.new(6) { tone(length: 3000, amplitude: 32_000) }
      samples = described_class.babble_noise(1000, speakers, seed: 3)
      expect(samples.max).to be <= 32_767
      expect(samples.min).to be >= -32_768
    end

    it 'refuses to build babble with no speakers' do
      expect { described_class.babble_noise(100, []) }.to raise_error(ArgumentError, /speaker/)
    end
  end

  describe '.mix_at_snr' do
    # The whole benchmark rests on this: measure the SNR back out of the
    # mixture and confirm it is what was asked for.
    [10, 5, 0, -5].each do |target_db|
      it "produces a mixture at #{target_db}dB SNR" do
        speech = tone(length: 24_000)
        noise = described_class.white_noise(24_000)

        mixed = described_class.mix_at_snr(speech, noise, target_db)
        residual = Array.new(speech.length) { |i| mixed[i] - speech[i] }

        measured = 20 * Math.log10(described_class.active_rms(speech) / described_class.rms(residual))
        expect(measured).to be_within(0.5).of(target_db)
      end
    end

    # A clip with silent head and tail must land at the labelled SNR over the
    # part that carries speech. Measuring the speech level across the silence
    # would inflate the noise gain and make the audio harder than the label —
    # every published number would then describe a condition nobody chose.
    it 'labels SNR against the speech, not the silence around it' do
      speech = Array.new(6000, 0) + tone(length: 12_000) + Array.new(6000, 0)
      noise = described_class.white_noise(speech.length)

      mixed = described_class.mix_at_snr(speech, noise, 0)
      residual = Array.new(speech.length) { |i| mixed[i] - speech[i] }

      measured = 20 * Math.log10(described_class.active_rms(speech) / described_class.rms(residual))
      expect(measured).to be_within(0.5).of(0)
    end

    it 'returns the speech untouched when there is no noise' do
      speech = tone(length: 500)
      expect(described_class.mix_at_snr(speech, [], 0)).to eq(speech)
    end

    it 'clips rather than wrapping around' do
      speech = Array.new(100, 32_000)
      noise = Array.new(100, 32_000)
      mixed = described_class.mix_at_snr(speech, noise, 0)
      expect(mixed.max).to be <= 32_767
      expect(mixed.min).to be >= -32_768
    end
  end

  describe '.active_rms' do
    it 'ignores the silent head and tail' do
      speech = tone(length: 12_000)
      padded = Array.new(6000, 0) + speech + Array.new(6000, 0)

      expect(described_class.active_rms(padded))
        .to be_within(1.0).of(described_class.active_rms(speech))
    end

    it 'is lower than whole-clip RMS is, for a padded clip' do
      padded = Array.new(6000, 0) + tone(length: 12_000) + Array.new(6000, 0)

      expect(described_class.rms(padded)).to be < described_class.active_rms(padded)
    end

    it 'falls back to the whole clip when nothing clears the floor' do
      flat = Array.new(1000, 100)
      expect(described_class.active_rms(flat)).to be_within(1.0).of(100)
    end

    it 'is zero for silence' do
      expect(described_class.active_rms(Array.new(1000, 0))).to eq(0.0)
    end
  end

  describe '.build' do
    it 'produces every white-noise condition without babble material' do
      speech = tone(length: 4800)
      conditions = described_class.build(speech)

      expect(conditions.keys).to contain_exactly('clean', 'white_+5dB', 'white_0dB')
      expect(conditions['clean']).to eq(speech)
    end

    it 'adds the babble conditions when speaker tracks are supplied' do
      speech = tone(length: 4800)
      speakers = [tone(length: 4800, freq: 300)]
      conditions = described_class.build(speech, babble_speakers: speakers)

      expect(conditions.keys).to include('babble_+5dB', 'babble_0dB')
      expect(conditions['babble_0dB'].length).to eq(speech.length)
    end

    it 'keeps every condition the same length as the source' do
      speech = tone(length: 4800)
      described_class.build(speech).each_value do |samples|
        expect(samples.length).to eq(speech.length)
      end
    end
  end
end
