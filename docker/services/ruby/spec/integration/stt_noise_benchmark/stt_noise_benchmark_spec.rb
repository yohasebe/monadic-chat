# frozen_string_literal: true

require 'spec_helper'
require_relative 'lib/runner'
require_relative 'lib/speech_source'

# The measurement itself. Opt-in and billed, so it is gated twice: RUN_API
# (the project-wide switch for specs that call providers) plus a switch of its
# own, because this one costs meaningfully more than a single chat round-trip.
#
# Scoring and mixing are pinned separately in wer_spec.rb / corpus_spec.rb,
# which run unconditionally — those are the parts that have to be right for a
# published number to mean anything.
RSpec.describe 'STT noise benchmark', :stt_noise_benchmark do
  before(:all) do
    skip 'RUN_API not enabled' unless ENV['RUN_API'] == 'true'
    skip 'set RUN_STT_NOISE_BENCH=true to run the billed benchmark' unless ENV['RUN_STT_NOISE_BENCH'] == 'true'
  end

  let(:truth) { File.read(File.join(__dir__, 'data', 'truth.txt')).strip }
  let(:output_dir) do
    File.join(Dir.pwd, 'tmp', 'stt_noise_benchmark', Time.now.strftime('%Y%m%d_%H%M%S'))
  end

  it 'measures every engine across every noise condition' do
    speech, rate = SttNoiseBenchmark::SpeechSource.load(text: truth)
    speakers = SttNoiseBenchmark::SpeechSource.babble_speakers(text: truth)

    runner = SttNoiseBenchmark::Runner.new(
      speech: speech,
      speech_rate: rate,
      truth: truth,
      babble_speakers: speakers
    )
    result = runner.run

    dir = SttNoiseBenchmark::Runner::Report.write(result, output_dir)
    puts "\n#{SttNoiseBenchmark::Runner::Report.to_markdown(result)}\n\nWritten to #{dir}"

    expect(result[:rows]).not_to be_empty

    # A run where nothing reached any provider is a broken harness, not a
    # finding. Individual engine failures are recorded and tolerated.
    successful = result[:rows].reject { |row| row[:error] }
    expect(successful).not_to be_empty, lambda {
      "every engine errored:\n#{result[:rows].map { |r| "#{r[:engine]}/#{r[:condition]}: #{r[:error]}" }.join("\n")}"
    }

    # Clean audio is the sanity check: if an engine cannot transcribe the
    # undegraded clip, its noise numbers say nothing about noise.
    clean = successful.select { |row| row[:condition] == 'clean' }
    expect(clean).not_to be_empty
  end
end
