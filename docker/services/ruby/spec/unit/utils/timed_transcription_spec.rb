# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"
require_relative "../../../lib/monadic/utils/timed_transcription"

# The shared timed transcription, with the Python container and the provider
# played: the segmenter writes segments.json and the decoded audio into the run
# folder, and each segment's WAV goes to `transcribe_bytes` (the Google/xAI way).
RSpec.describe Monadic::Utils::TimedTranscription do
  around do |example|
    Dir.mktmpdir("timed-transcription") do |dir|
      @data = File.join(dir, "data")
      FileUtils.mkdir_p(File.join(@data, "conversations", "c1", "artifacts"))
      example.run
    end
  end

  let!(:job) do
    allow(Monadic::Utils::Environment).to receive(:data_path).and_return(@data)
    Monadic::Workspace::Jobs.create!("conversations/c1")
  end
  let(:segments_doc) do
    { "schema" => "speech-segments", "schema_version" => 1, "sample_rate_hz" => 24_000,
      "timebase" => "video_relative_samples", "status" => "complete", "timeline_origin_ms" => 0.0,
      "segments" => [{ "segment_id" => "seg000001", "start_sample" => 0, "end_sample" => 24_000 },
                     { "segment_id" => "seg000002", "start_sample" => 48_000, "end_sample" => 72_000 }] }
  end
  let(:segmenter_stderr) { "" }

  before do
    allow(Monadic::Utils::Environment).to receive(:data_path).and_return(@data)
    allow(Monadic::Shell).to receive(:exec) do |argv:, **|
      expect(argv.first(2)).to eq(["python", described_class::SEGMENT_SCRIPT])
      if segmenter_stderr.empty?
        File.write(File.join(job[:path], "segments.json"), segments_doc.to_json)
        File.binwrite(File.join(job[:path], "audio_24k.pcm"), "\0".b * 200_000)
      end
      ["", segmenter_stderr, double(success?: segmenter_stderr.empty?)]
    end
  end

  def transcription(transcribe:, cancelled: -> { false })
    described_class.new(provider: "xai", model: "grok-stt", api_key: "k", input: "/monadic/data/in.mp3",
                        job: job, output: "/monadic/data/#{job[:relative]}", cancelled: cancelled,
                        transcribe_bytes: transcribe)
  end

  def saved
    JSON.parse(File.read(File.join(job[:path], "transcript.json")))
  end

  def pcm_left?
    File.exist?(File.join(job[:path], "audio_24k.pcm"))
  end

  it "transcribes each segment, keeps the transcript and subtitles, and removes the decoded audio" do
    texts = ["Hello there.", "Goodbye."]
    result = transcription(transcribe: ->(_wav) { texts.shift }).run
    expect(result[:text]).to eq("[00:00–00:01] Hello there.\n[00:02–00:03] Goodbye.")
    expect(result[:subtitles].keys).to contain_exactly(:vtt, :srt)
    expect(saved["status"]).to eq("complete")
    expect(pcm_left?).to be(false)
  end

  it "keeps the segments done so far, marked stopped, when its thread is stopped (Reset or Cancel)" do
    first_done = Queue.new
    calls = 0
    run = Thread.new do
      transcription(transcribe: lambda { |_wav|
        calls += 1
        next "Hello there." if calls == 1

        first_done << true
        sleep 30
      }).run
    end
    first_done.pop
    run.kill
    run.join(10)

    expect(saved["status"]).to eq("stopped")
    expect(saved["segments"].map { |s| s["status"] }).to eq(%w[complete pending])
    expect(saved["segments"].first["text"]).to eq("Hello there.")
    expect(pcm_left?).to be(false)
  end

  it "asks the segmenter for the audio clock and track for an audio file, and keeps the video command as it was" do
    seen = []
    allow(Monadic::Shell).to receive(:exec) do |argv:, **|
      seen << argv
      ["", "", double(success?: false)]
    end
    transcription(transcribe: ->(_wav) { "" }).run
    described_class.new(provider: "xai", model: "m", api_key: "k", input: "/monadic/data/a.mp3", job: job,
                        output: "/out", cancelled: -> { false }, timeline: :audio, audio_stream: 1,
                        transcribe_bytes: ->(_wav) { "" }).run
    expect(seen[0]).to eq(["python", described_class::SEGMENT_SCRIPT, "/monadic/data/in.mp3", "/monadic/data/#{job[:relative]}"])
    expect(seen[1]).to eq(["python", described_class::SEGMENT_SCRIPT, "/monadic/data/a.mp3", "/out",
                           "--timeline", "audio", "--audio-stream", "1"])
  end

  it "takes a script that does not know the audio clock for an old Python container" do
    expect(described_class.old_python_image?("speech_segments.py: error: unrecognized arguments: --timeline audio")).to be(true)
  end

  it "says what the times count from for an audio track that starts later" do
    doc = { "status" => "complete", "sample_rate_hz" => 24_000, "timebase" => "audio_relative_samples",
            "timeline_origin_ms" => 2000.0,
            "segments" => [{ "status" => "complete", "start_sample" => 0, "end_sample" => 24_000, "text" => "Hi." }] }
    expect(described_class.format_transcript(doc)).to include("count from the start of the audio track, which a player shows at 00:02")
  end

  it "says when the transcript could not be saved, and does not leave a stopped one in its place" do
    allow(File).to receive(:rename).and_call_original
    allow(File).to receive(:rename).with(a_string_ending_with("transcript.json.part-#{Process.pid}"), anything)
                                   .and_raise(Errno::ENOSPC)
    texts = ["Hello there.", "Goodbye."]
    result = transcription(transcribe: ->(_wav) { texts.shift }).run
    expect(result[:text]).to eq("Audio transcription failed: the transcript could not be saved in the run folder (ENOSPC).")
    expect(File.exist?(File.join(job[:path], "transcript.json"))).to be(false)
    expect(Dir.children(job[:path]).grep(/\.part-/)).to be_empty
    expect(pcm_left?).to be(false)
  end

  it "keeps the whole result when stopped while saving it" do
    # Plain Ruby, not an RSpec stub: a stub called in the killed thread would
    # stay locked for the call made afterwards. The first save is stopped
    # half-written; the ones after it are the real save.
    writing = Queue.new
    stalled = Class.new(described_class) do
      define_method(:save) do |result|
        return super(result) if @stalled

        @stalled = true
        partial = File.join(@job[:path], "transcript.json.part-#{Process.pid}")
        begin
          File.write(partial, "{")
          writing << true
          sleep 30
        ensure
          File.delete(partial) if File.exist?(partial)
        end
      end
    end
    texts = ["Hello there.", "Goodbye."]
    run = Thread.new do
      stalled.new(provider: "xai", model: "grok-stt", api_key: "k", input: "/monadic/data/in.mp3", job: job,
                  output: "/monadic/data/#{job[:relative]}", cancelled: -> { false },
                  transcribe_bytes: ->(_wav) { texts.shift }).run
    end
    writing.pop
    run.kill
    run.join(10)
    expect(saved["status"]).to eq("complete")
    expect(saved["segments"].map { |s| s["text"] }).to eq(["Hello there.", "Goodbye."])
    expect(Dir.children(job[:path]).grep(/\.part-/)).to be_empty
    expect(pcm_left?).to be(false)
  end

  it "tells each attempt as it is sent, retries included" do
    sent = []
    calls = 0
    described_class.new(provider: "xai", model: "grok-stt", api_key: "k", input: "/monadic/data/in.mp3", job: job,
                        output: "/monadic/data/#{job[:relative]}", cancelled: -> { false },
                        on_attempt: ->(seconds) { sent << seconds },
                        transcribe_bytes: ->(_wav) { (calls += 1) == 1 ? "ERROR: lost" : "text" }).run
    expect(sent).to eq([1.0, 1.0, 1.0]) # the first segment twice (one retry), then the second
  end

  it "keeps where an audio file came from in the transcript" do
    segments_doc["source"] = { "timeline" => "audio", "audio_stream" => 1, "player_offset_ms" => 0.0 }
    texts = ["Hello there.", "Goodbye."]
    transcription(transcribe: ->(_wav) { texts.shift }).run
    expect(saved["source"]).to include("audio_stream" => 1)
  end

  it "removes the decoded audio even when stopped before any segment was sent" do
    reached = Queue.new
    allow(Monadic::Utils::SegmentTranscriber::Batch).to receive(:new).and_wrap_original do |original, **args|
      reached << true
      sleep 30
      original.call(**args)
    end
    run = Thread.new { transcription(transcribe: ->(_wav) { "x" }).run }
    reached.pop
    run.kill
    run.join(10)
    expect(File.exist?(File.join(job[:path], "transcript.json"))).to be(false)
    expect(pcm_left?).to be(false)
  end

  it "is only for the providers with their own segment transcription, each through its own way" do
    expect { described_class.new(provider: "anthropic", model: "m", api_key: "k", input: "i", job: job, output: "o", cancelled: -> { false }) }
      .to raise_error(ArgumentError, /no timed transcription/)
    expect { described_class.new(provider: "xai", model: "m", api_key: "k", input: "i", job: job, output: "o", cancelled: -> { false }) }
      .to raise_error(ArgumentError, /needs transcribe_bytes/)
  end

  it "says the Python container is too old, without sending anything" do
    allow(Monadic::Shell).to receive(:exec)
      .and_return(["", "python: can't open file '#{described_class::SEGMENT_SCRIPT}'", double(success?: false)])
    sent = []
    expect(transcription(transcribe: ->(wav) { sent << wav }).run).to eq(fallback: true)
    expect(sent).to be_empty
  end

  it "says when no speech was found, without sending anything" do
    segments_doc.merge!("status" => "no_speech_detected", "segments" => [])
    sent = []
    expect(transcription(transcribe: ->(wav) { sent << wav }).run[:text]).to eq("(No speech was detected in the audio.)")
    expect(sent).to be_empty
  end
end
