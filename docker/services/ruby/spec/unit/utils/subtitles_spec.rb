# frozen_string_literal: true

require "spec_helper"
require_relative "../../../lib/monadic/utils/subtitles"

RSpec.describe Monadic::Utils::Subtitles do
  let(:result) do
    { "sample_rate_hz" => 24_000,
      "segments" => [
        { "status" => "complete", "start_sample" => 2_112, "end_sample" => 61_200, "text" => "おっと危な。" },
        { "status" => "complete", "start_sample" => 72_000, "end_sample" => 96_000, "text" => "  " },
        { "status" => "failed", "start_sample" => 100_000, "end_sample" => 120_000, "text" => nil },
        { "status" => "complete", "start_sample" => 3_600 * 24_000, "end_sample" => (3_602.5 * 24_000).to_i,
          "text" => "first line\n\n\nsecond --> line" }
      ] }
  end

  it "writes an SRT cue for each segment with words, timed to the millisecond" do
    expect(described_class.srt(result)).to eq(<<~SRT)
      1
      00:00:00,088 --> 00:00:02,550
      おっと危な。

      2
      01:00:00,000 --> 01:00:02,500
      first line
      second -> line
    SRT
  end

  it "writes WebVTT with its header and dot-separated milliseconds" do
    vtt = described_class.vtt(result)
    expect(vtt).to start_with("WEBVTT\n\n00:00:00.088 --> 00:00:02.550\nおっと危な。\n")
    expect(vtt).to include("01:00:00.000 --> 01:00:02.500\nfirst line\nsecond --&gt; line\n")
  end

  it "escapes WebVTT markup so the words show as said, and leaves SRT text as it is" do
    said = { "sample_rate_hz" => 24_000,
             "segments" => [{ "status" => "complete", "start_sample" => 0, "end_sample" => 24_000,
                              "text" => "Say <b>bold</b> &amp; x" }] }
    expect(described_class.vtt(said)).to include("\nSay &lt;b&gt;bold&lt;/b&gt; &amp;amp; x\n")
    expect(described_class.srt(said)).to include("\nSay <b>bold</b> &amp; x\n")
  end

  it "times the cues on the player's clock when the picture starts after the file's zero" do
    late = result.merge("timeline_origin_ms" => 1014.0)
    expect(described_class.vtt(late)).to start_with("WEBVTT\n\n00:00:01.102 --> 00:00:03.564\n")
    expect(described_class.srt(late)).to include("01:00:01,014 --> 01:00:03,514")
  end

  it "starts at zero when the first frame is before the file's zero, as players show it" do
    early = result.merge("timeline_origin_ms" => -1000.0)
    expect(described_class.vtt(early)).to start_with("WEBVTT\n\n00:00:00.088 --> 00:00:02.550\n")
  end

  it "leaves out a segment whose end is not after its start" do
    odd = { "sample_rate_hz" => 24_000,
            "segments" => [{ "status" => "complete", "start_sample" => 48_000, "end_sample" => 48_000, "text" => "x" }] }
    expect(described_class.cues(odd)).to eq([])
  end

  it "has no cues when nothing was transcribed" do
    expect(described_class.cues("sample_rate_hz" => 24_000, "segments" => [])).to eq([])
    expect(described_class.vtt("sample_rate_hz" => 24_000, "segments" => [])).to eq("WEBVTT\n")
  end
end
