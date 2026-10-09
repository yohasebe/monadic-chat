# frozen_string_literal: true

require "spec_helper"
require "json"
require_relative "../../../lib/monadic/utils/video_probe"

# The rules applied to what ffprobe reports. ffprobe itself is answered here;
# the same rules were run against real files in the Python container (see
# the stage notes) and the attachment path in video_analyze_agent_spec goes
# through check! with an ffprobe answer.
RSpec.describe Monadic::Utils::VideoProbe do
  let(:answer) do
    { "streams" => [{ "codec_type" => "video", "codec_name" => "h264", "width" => 1280, "height" => 720, "disposition" => { "attached_pic" => 0 } },
                    { "codec_type" => "audio", "codec_name" => "aac" }],
      "format" => { "format_name" => "mov,mp4,m4a,3gp,3g2,mj2", "duration" => "600.0" } }
  end
  let(:argvs) { [] }

  def probe(path: "/monadic/data/conversations/x/inputs/a_1__clip.mp4", stdout: answer.to_json, success: true)
    allow(Monadic::Shell).to receive(:exec) do |container:, argv:, timeout:|
      argvs << [container, argv, timeout]
      [stdout, "", double(success?: success)]
    end
    described_class.check!(path)
  end

  def rejection(**kwargs)
    probe(**kwargs)
    nil
  rescue described_class::Rejected => e
    [e.reason, e.message]
  end

  it "accepts a video that fits and reports what it found" do
    expect(probe).to eq({ duration: 600.0, width: 1280, height: 720, audio: true })
    container, argv, timeout = argvs.first
    expect(container).to eq(:python)
    expect(argv.first).to eq("ffprobe")
    expect(argv.last).to eq("/monadic/data/conversations/x/inputs/a_1__clip.mp4")
    expect(timeout).to eq(described_class::PROBE_TIMEOUT)
  end

  it "refuses before running ffprobe when the extension is not a video type" do
    expect(rejection(path: "/monadic/data/notes.txt").first).to eq(:extension)
    expect(rejection(path: "/monadic/data/noext").first).to eq(:extension)
    expect(argvs).to be_empty
  end

  it "refuses a file ffprobe cannot read" do
    expect(rejection(stdout: "{}", success: false).first).to eq(:unreadable)
    expect(rejection(stdout: "not json").first).to eq(:unreadable)
  end

  it "refuses a format that is not the one the extension names" do
    answer["format"]["format_name"] = "matroska,webm"
    expect(rejection.first).to eq(:format)
  end

  it "refuses a file without a video track, counting a cover picture as none" do
    answer["streams"] = [{ "codec_type" => "audio", "codec_name" => "aac" }]
    expect(rejection.first).to eq(:no_video)
    answer["streams"] = [{ "codec_type" => "video", "codec_name" => "mjpeg", "width" => 600, "height" => 600, "disposition" => { "attached_pic" => 1 } },
                         { "codec_type" => "audio", "codec_name" => "aac" }]
    expect(rejection.first).to eq(:no_video)
  end

  it "refuses a second picture track, or a cover picture ahead of the video" do
    answer["streams"] << { "codec_type" => "video", "codec_name" => "h264", "width" => 640, "height" => 360, "disposition" => { "attached_pic" => 0 } }
    expect(rejection.first).to eq(:streams)
    answer["streams"].pop
    answer["streams"].unshift({ "codec_type" => "video", "codec_name" => "mjpeg", "width" => 600, "height" => 600, "disposition" => { "attached_pic" => 1 } })
    expect(rejection.first).to eq(:streams)
  end

  it "accepts a cover picture that follows the video" do
    answer["streams"] << { "codec_type" => "video", "codec_name" => "mjpeg", "width" => 600, "height" => 600, "disposition" => { "attached_pic" => 1 } }
    expect(probe[:width]).to eq(1280)
  end

  it "refuses a codec outside the list" do
    answer["streams"][0]["codec_name"] = "gif"
    expect(rejection.first).to eq(:codec)
  end

  it "refuses a length it cannot read, zero, or over 50 minutes" do
    [nil, "N/A", "0", "-1", "nan", "inf"].each do |value|
      answer["format"]["duration"] = value
      expect(rejection.first).to eq(:duration), value.inspect
    end
    answer["format"]["duration"] = "3000.0"
    expect(probe[:duration]).to eq(3000.0)
    answer["format"]["duration"] = "3000.5"
    expect(rejection).to eq([:too_long, "The video is 51 minutes long; videos up to 50 minutes can be analyzed."])
  end

  it "refuses a picture larger than the limit on either side, or with no size" do
    [[4097, 100], [100, 4097], [0, 720], [nil, nil]].each do |w, h|
      answer["streams"][0]["width"] = w
      answer["streams"][0]["height"] = h
      expect(rejection.first).to eq(:dimensions), [w, h].inspect
    end
    answer["streams"][0]["width"] = 4096
    answer["streams"][0]["height"] = 2160
    expect(probe[:width]).to eq(4096)
  end

  it "reports a probe that ran too long as unreadable" do
    allow(Monadic::Shell).to receive(:exec).and_raise(Monadic::Shell::TimedOut)
    expect { described_class.check!("/monadic/data/a.mp4") }
      .to raise_error(described_class::Rejected) { |e| expect(e.reason).to eq(:unreadable) }
  end
end
