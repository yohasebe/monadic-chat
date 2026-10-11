# frozen_string_literal: true

require "spec_helper"
require_relative "../../../lib/monadic/utils/audio_probe"

RSpec.describe Monadic::Utils::AudioProbe do
  def info(format: "mp3", duration: "61.5", streams: %w[audio])
    { "format" => { "format_name" => format, "duration" => duration },
      "streams" => streams.map { |t| { "codec_type" => t } } }
  end

  it "takes an audio file whose format matches its extension" do
    expect(described_class.evaluate(info, %w[mp3])).to eq(duration: 61.5, tracks: 1)
    expect(described_class.evaluate(info(format: "mov,mp4,m4a,3gp,3g2,mj2", streams: %w[audio audio video]), %w[mov mp4]))
      .to eq(duration: 61.5, tracks: 2)
  end

  it "refuses what it should not decode, saying why" do
    expect { described_class.evaluate(info(format: "wav"), %w[mp3]) }.to raise_error(described_class::Rejected) { |e| expect(e.reason).to eq(:format) }
    expect { described_class.evaluate(info(streams: %w[video]), %w[mp3]) }.to raise_error(described_class::Rejected) { |e| expect(e.reason).to eq(:no_audio) }
    expect { described_class.evaluate(info(duration: "N/A"), %w[mp3]) }.to raise_error(described_class::Rejected) { |e| expect(e.reason).to eq(:duration) }
    expect { described_class.evaluate(info(duration: "3000.5"), %w[mp3]) }
      .to raise_error(described_class::Rejected, /51 minutes long; recordings up to 50 minutes/)
  end

  it "refuses an extension it does not know before running anything" do
    expect(Monadic::Shell).not_to receive(:exec)
    expect { described_class.check!("/monadic/data/notes.txt") }.to raise_error(described_class::Rejected) { |e| expect(e.reason).to eq(:extension) }
  end
end
