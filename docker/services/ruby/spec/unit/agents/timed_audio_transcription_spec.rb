# frozen_string_literal: true

require "rspec"
require "json"
require "tmpdir"
require "fileutils"
require "stringio"
require "http"
require_relative "../../../lib/monadic/agents/audio_transcription_agent"
require_relative "../../../lib/monadic/adapters/file_analysis_helper"

# analyze_audio on an audio file in the shared folder, with the Python
# container and the provider played: ffprobe answers, the segmenter writes
# its segments into the run folder it is given, and the segments' transcript
# comes back from the transcriber.
RSpec.describe "Transcribing an audio file with times" do
  let(:host) do
    Class.new do
      include AudioTranscriptionAgent
      include MonadicHelper
      attr_accessor :settings

      def initialize
        @settings = { "provider" => "openai" }
      end
    end.new
  end

  around do |example|
    Dir.mktmpdir("timed-audio") do |dir|
      @data = File.join(dir, "data")
      @state = File.join(dir, "state")
      FileUtils.mkdir_p(@data)
      example.run
    end
  end

  let(:ledger) { Monadic::Workspace::Ledger.new(File.join(@state, "ledger.json")) }
  let(:chat_id) { Monadic::Workspace::Ids.generate(:chat) }
  let(:session) { { chat_id: chat_id, parameters: {}, runtime_settings: { language: "en" } } }
  let(:probe_answer) { { "format" => { "format_name" => "mp3", "duration" => "1800.0" }, "streams" => [{ "codec_type" => "audio" }] } }
  let(:segmenter_calls) { [] }
  let(:segmenter_stderr) { "" }
  let(:transcriber_args) { {} }
  let(:segments_doc) do
    { "schema" => "speech-segments", "sample_rate_hz" => 24_000, "timebase" => "audio_relative_samples",
      "status" => "complete", "timeline_origin_ms" => 0.0,
      "segments" => [{ "segment_id" => "seg000001", "start_sample" => 72_000, "end_sample" => 120_000 }] }
  end

  before do
    stub_const("CONFIG", { "OPENAI_API_KEY" => "test-key-not-sent" })
    allow(Monadic::Utils::Environment).to receive(:data_path).and_return(@data)
    allow(Monadic::Utils::Environment).to receive(:state_path).and_return(@state)
    allow(Monadic::Workspace::Ledger).to receive(:default).and_return(ledger)
    allow(Monadic::Shell).to receive(:exec) do |argv:, **|
      next [probe_answer.to_json, "", double(success?: true)] if argv.first == "ffprobe"

      segmenter_calls << argv
      if segmenter_stderr.empty?
        out = File.join(File.realpath(@data), argv[3].delete_prefix("/monadic/data/"))
        File.write(File.join(out, "segments.json"), segments_doc.to_json)
        File.binwrite(File.join(out, "audio_24k.pcm"), "\0".b * 240_000)
      end
      ["", segmenter_stderr, double(success?: segmenter_stderr.empty?)]
    end
    allow(Monadic::Utils::SegmentTranscriber).to receive(:new) do |**args|
      transcriber_args.merge!(args)
      doc = segments_doc.merge("schema" => "timed-transcript", "status" => "complete",
                               "segments" => [segments_doc["segments"][0].merge("status" => "complete", "text" => "Good morning.")])
      double(run: doc)
    end
    # A recording larger than the 25 MB the whole-file way takes.
    File.open(File.join(@data, "lecture.mp3"), "wb") { |f| f.truncate(30 * 1024 * 1024) }
  end

  # The session of a real chat: a Rack session object, which is not a Hash.
  def rack_session(values)
    require "rack/session/abstract/id"
    store = Object.new
    def store.load_session(_req) = ["sid", {}]
    def store.session_exists?(_req) = false
    Rack::Session::Abstract::SessionHash.new(store, Object.new).tap do |s|
      values.each { |k, v| s[k] = v }
    end
  end

  it "reads the chat and its language from a real Rack session, which is not a Hash" do
    real = rack_session(chat_id: chat_id, parameters: {}, runtime_settings: { language: "ja" })
    expect(real).not_to be_a(Hash)
    answer = host.analyze_audio(audio: "lecture.mp3", session: real)
    expect(answer).to include("[00:03–00:05] Good morning.")
    expect(transcriber_args[:language]).to eq("ja")
  end

  it "gives each line the time in the recording, with no 25 MB limit, and keeps the run in the chat's folder" do
    answer = host.analyze_audio(audio: "lecture.mp3", session: session)
    expect(answer).to include("[00:03–00:05] Good morning.")
    expect(answer).to match(%r{Subtitles: /data/pub_[a-z0-9]{16}\.vtt \(WebVTT\), /data/pub_[a-z0-9]{16}\.srt \(SRT\)})
    expect(answer).to match(%r{Saved in the chat's folder: conversations/[^/]+/artifacts/j_[a-z0-9]{16}/transcript\.json})
    expect(segmenter_calls.first.last(2)).to eq(%w[--timeline audio])
    expect(segmenter_calls.first[2]).to eq("/monadic/data/lecture.mp3")
    expect(transcriber_args[:language]).to eq("en")
    workspace = ledger.workspace_for_chat(chat_id)
    artifacts = JSON.parse(File.read(ledger.path))["artifacts"].values
    expect(artifacts.map { |a| a["kind"] }).to contain_exactly("subtitle_vtt", "subtitle_srt")
    expect(artifacts).to all(include("owner" => "chat", "chat_id" => chat_id, "workspace_id" => workspace[:workspace_id]))
  end

  it "says why an Opus or AAC file cannot go the whole-file way" do
    File.binwrite(File.join(@data, "talk.opus"), "OggS")
    expect(host).not_to receive(:audio_transcription_agent)
    expect(host.analyze_audio(audio: "talk.opus", session: nil)).to start_with("Error: .opus files are transcribed only with times")
  end

  it "does not name a saved transcript when it could not be saved" do
    allow(Monadic::Utils::SharedFs).to receive(:write_new).and_call_original
    allow(Monadic::Utils::SharedFs).to receive(:write_new).with(anything, "transcript.json", any_args)
                                                          .and_raise(Errno::ENOSPC)
    answer = host.analyze_audio(audio: "lecture.mp3", session: session)
    expect(answer).to include("could not be saved")
    expect(answer).not_to include("Saved in the chat's folder")
  end

  it "uses the whole-file way when there is no chat to keep the run in" do
    allow(host).to receive(:audio_transcription_agent).and_return("Untimed text.")
    expect(host.analyze_audio(audio: "lecture.mp3", session: nil)).to eq("Untimed text.")
    expect(segmenter_calls).to be_empty
  end

  it "says why when the Python container is too old for times" do
    allow(host).to receive(:audio_transcription_agent).and_return("Untimed text.")
    allow(Monadic::Shell).to receive(:exec) do |argv:, **|
      next [probe_answer.to_json, "", double(success?: true)] if argv.first == "ffprobe"

      ["", "speech_segments.py: error: unrecognized arguments: --timeline audio", double(success?: false)]
    end
    answer = host.analyze_audio(audio: "lecture.mp3", session: session)
    expect(answer).to start_with("Untimed text.")
    expect(answer).to include(AudioTranscriptionAgent::TIMED_AUDIO_UNTIMED_NOTE)
  end

  it "refuses a recording longer than 50 minutes before decoding it" do
    probe_answer["format"]["duration"] = "3100"
    expect(host.analyze_audio(audio: "lecture.mp3", session: session)).to match(/52 minutes long; recordings up to 50 minutes/)
    expect(segmenter_calls).to be_empty
  end

  it "refuses a file that is not in the shared folder" do
    expect(host.analyze_audio(audio: "missing.mp3", session: session)).to eq("Error: missing.mp3 was not found in the shared folder.")
  end

  it "uses only the app's own provider: none without its own speech-to-text" do
    host.settings = { "provider" => "anthropic" }
    allow(host).to receive(:audio_transcription_agent).and_return("ERROR: not supported")
    expect(host.analyze_audio(audio: "lecture.mp3", session: session)).to eq("ERROR: not supported")
    expect(segmenter_calls).to be_empty
  end

  describe "an attached audio file" do
    def attach(chat: chat_id, purpose: "audio", name: "talk.mp3", body: "ID3\x04\x00".b + ("x" * 2000))
      Monadic::Workspace::Attachments.accept!(chat_id: chat, app_name: "SpeechDraftHelperOpenAI", purpose: purpose,
                                              original_name: name, source: StringIO.new(body), ledger: ledger)
    end

    # As when the attachments were sent with a message of this chat: the
    # tools answering it may take them.
    def as_sent(*records, &block)
      context = Monadic::Workspace::RequestContext.new(chat_id: chat_id, attachment_ids: records.map { |r| r[:attachment_id] })
      Monadic::Workspace::RequestContext.with(context, &block)
    end

    it "is transcribed from the chat's folder, with the run kept beside it" do
      record = attach
      answer = as_sent(record) { host.analyze_audio(attachment_id: record[:attachment_id], session: session) }
      expect(answer).to include("[00:03–00:05] Good morning.")
      expect(segmenter_calls.first[2]).to eq("/monadic/data/#{record[:relative_path]}")
      expect(segmenter_calls.first[3]).to include("/artifacts/j_")
      expect(File.dirname(segmenter_calls.first[3])).to eq(File.join(File.dirname(File.dirname(segmenter_calls.first[2])), "artifacts"))
      artifacts = JSON.parse(File.read(ledger.path))["artifacts"].values
      expect(artifacts.size).to eq(2)
      expect(artifacts).to all(include("owner" => "chat", "chat_id" => chat_id, "workspace_id" => record[:workspace_id]))
    end

    it "is found from a real Rack session too (the session of an actual chat)" do
      record = attach
      real = rack_session(chat_id: chat_id, parameters: {})
      expect(as_sent(record) { host.analyze_audio(audio: record[:attachment_id], session: real) }).to include("Good morning.")
    end

    it "is found when the model passes its id as the file name" do
      record = attach
      expect(as_sent(record) { host.analyze_audio(audio: record[:attachment_id], session: session) }).to include("Good morning.")
    end

    it "is refused when no message of the chat sent it (uploaded only, or its id written somewhere)" do
      record = attach
      expect(as_sent { host.analyze_audio(attachment_id: record[:attachment_id], session: session) }).to start_with("Error:")
      expect(host.analyze_audio(audio: record[:attachment_id], session: session)).to start_with("Error:")
      expect(as_sent { host.analyze_audio(audio: record[:attachment_id], session: session) }).to start_with("Error:")
      expect(segmenter_calls).to be_empty
    end

    it "is refused in another chat, and a video attachment is not taken as audio" do
      record = attach
      other = session.merge(chat_id: Monadic::Workspace::Ids.generate(:chat))
      expect(as_sent(record) { host.analyze_audio(attachment_id: record[:attachment_id], session: other) }).to start_with("Error:")
      video = attach(purpose: "video", name: "clip.mp4", body: "\x00\x00\x00\x18ftypmp42\x00\x00\x00\x00mp42isom".b + ("x" * 2000))
      expect(as_sent(video) { host.analyze_audio(attachment_id: video[:attachment_id], session: session) }).to eq("Error: attachment clip.mp4 is not an audio file.")
      expect(segmenter_calls).to be_empty
    end
  end
end
