# frozen_string_literal: true

require 'rspec'
require 'json'
require 'stringio'
require 'fileutils'
require 'tmpdir'
require 'http'
require_relative '../../../lib/monadic/agents/image_analysis_agent'
require_relative '../../../lib/monadic/agents/audio_transcription_agent'
require_relative '../../../lib/monadic/agents/video_analyze_agent'

RSpec.describe VideoAnalyzeAgent do
  # Define a test helper class at file scope to avoid constant redefinition warnings
  let(:test_class) do
    Class.new do
      include ImageAnalysisAgent
      include AudioTranscriptionAgent
      include VideoAnalyzeAgent

      attr_accessor :settings

      def initialize
        @settings = { "provider" => "openai", "model" => "gpt-4.1" }
      end

      def session
        @session ||= { parameters: {} }
      end

      # What the extractor in the Python container prints (Monadic::Shell.exec
      # is answered with it below).
      attr_writer :extractor_output

      def extractor_output
        @extractor_output || <<~OUTPUT
          13 frames extracted
          Base64-encoded frames saved to ./frames_20250629_154801.json
          Audio extracted to ./audio_20250629_154802.mp3
        OUTPUT
      end

      # Mock audio_transcription_agent (replaces stt_query.rb delegation)
      def audio_transcription_agent(audio_path:, model: nil, response_format: "text", lang_code: nil)
        "Hello world, this is the audio transcript."
      end
    end
  end

  before do
    # Pin the shared volume to the container path so File.exist? stubs below
    # remain stable regardless of host machine. The agent resolves paths
    # through `Monadic::Utils::Environment.shared_volume`; the legacy
    # `defined?(SHARED_VOL)` lookup never resolved from the agent module's
    # lexical scope and was masking the real path behavior in production.
    allow(Monadic::Utils::Environment).to receive(:shared_volume).and_return("/monadic/data")
    # The way by file name; the check before decoding is exercised for real
    # in 'analyzing an attachment' below and in video_probe_spec.
    allow(Monadic::Utils::SharedPathGuard).to receive(:command_path) { |file, **| "/monadic/data/#{file}" }
    allow(Monadic::Utils::VideoProbe).to receive(:check!).and_return({ duration: 3.0, width: 320, height: 240, audio: true })
    allow(Monadic::Shell).to receive(:exec) do |container:, argv:, **|
      extractor_calls << { container: container, argv: argv }
      [agent.extractor_output, "", double(success?: true)]
    end
  end

  let(:extractor_calls) { [] }

  let(:agent) { test_class.new }

  # Sample frames data (small base64 PNG stubs)
  let(:sample_frames) { ["iVBORw0KGgo=", "iVBORw0KGgo=", "iVBORw0KGgo="] }
  let(:sample_frames_json) { JSON.generate(sample_frames) }

  before do
    allow(ImageAnalysisAgent).to receive(:vision_model_for).and_return("test-vision-model")
    # Also stub CONFIG
    stub_const("CONFIG", {
      "OPENAI_API_KEY" => "test-openai-key",
      "EXTRA_LOGGING" => nil
    })
  end

  describe '#analyze_video' do
    context 'when video processing is successful' do
      before do
        # Stub file reading for frames JSON
        allow(File).to receive(:exist?).and_call_original
        allow(File).to receive(:exist?).with("./frames_20250629_154801.json").and_return(false)
        allow(File).to receive(:exist?).with("/monadic/data/frames_20250629_154801.json").and_return(true)
        allow(File).to receive(:read).with("/monadic/data/frames_20250629_154801.json").and_return(sample_frames_json)

        # Stub Vision API call
        allow(agent).to receive(:video_vision_openai).and_return("This is a video showing a deer crossing the road.")
      end

      it 'extracts frames and returns video description with audio transcript' do
        result = agent.analyze_video(file: "test.mp4", fps: 1, query: "What is happening?")

        expect(result).to include("This is a video showing a deer crossing the road")
        expect(result).to include("Audio Transcript:")
        expect(result).to include("Hello world")
      end

      it 'handles video without query parameter' do
        result = agent.analyze_video(file: "test.mp4", fps: 1)

        expect(result).to include("This is a video showing a deer crossing the road")
      end

      it 'runs only the extractor in the Python container (no video_query or stt_query)' do
        agent.analyze_video(file: "test.mp4", fps: 1)

        expect(extractor_calls.size).to eq(1)
        expect(extractor_calls.first[:container]).to eq(:python)
        expect(extractor_calls.first[:argv].first(2)).to eq(["python", VideoAnalyzeAgent::EXTRACT_SCRIPT])
      end
    end

    context 'when frame extraction fails' do
      it 'returns error message when no JSON file is found' do
        agent.extractor_output = "Error: Failed to extract frames"

        result = agent.analyze_video(file: "test.mp4")

        expect(result).to include("Error: Failed to extract frames from video")
      end
    end

    context 'when file parameter is missing' do
      it 'returns error message for nil' do
        result = agent.analyze_video(file: nil)
        expect(result).to eq("Error: attachment_id or file is required.")
      end

      it 'returns error message for empty string' do
        result = agent.analyze_video(file: "")
        expect(result).to eq("Error: attachment_id or file is required.")
      end
    end

    context 'when frames JSON file is not found' do
      before do
        local_shared = File.expand_path(File.join(Dir.home, "monadic", "data"))
        allow(File).to receive(:exist?).and_call_original
        allow(File).to receive(:exist?).with("./frames_20250629_154801.json").and_return(false)
        allow(File).to receive(:exist?).with("/monadic/data/frames_20250629_154801.json").and_return(false)
        allow(File).to receive(:exist?).with(File.join(local_shared, "frames_20250629_154801.json")).and_return(false)
      end

      it 'returns error about missing file' do
        result = agent.analyze_video(file: "test.mp4")
        expect(result).to include("ERROR: Frames JSON file not found")
      end
    end

    context 'output without audio file' do
      before do
        agent.extractor_output = "15 frames extracted\nBase64-encoded frames saved to ./frames_only.json"
        allow(File).to receive(:exist?).and_call_original
        allow(File).to receive(:exist?).with("./frames_only.json").and_return(false)
        allow(File).to receive(:exist?).with("/monadic/data/frames_only.json").and_return(true)
        allow(File).to receive(:read).with("/monadic/data/frames_only.json").and_return(sample_frames_json)
        allow(agent).to receive(:video_vision_openai).and_return("Video description only")
      end

      it 'returns description without audio transcript' do
        result = agent.analyze_video(file: "test.mp4")

        expect(result).to include("Video description only")
        expect(result).not_to include("Audio Transcript:")
      end
    end

    context 'error handling' do
      before do
        allow(File).to receive(:exist?).and_call_original
        allow(File).to receive(:exist?).with("./frames_20250629_154801.json").and_return(false)
        allow(File).to receive(:exist?).with("/monadic/data/frames_20250629_154801.json").and_return(true)
        allow(File).to receive(:read).with("/monadic/data/frames_20250629_154801.json").and_return(sample_frames_json)
      end

      it 'returns video analysis error when Vision API fails' do
        allow(agent).to receive(:video_vision_openai).and_return("ERROR: OpenAI Vision API error (500): Internal server error")

        result = agent.analyze_video(file: "test.mp4")

        expect(result).to include("Video analysis failed:")
      end

      it 'includes audio error in output when audio transcription fails' do
        allow(agent).to receive(:video_vision_openai).and_return("Video description")
        agent.extractor_output = "Base64-encoded frames saved to ./frames_20250629_154801.json\nAudio extracted to ./audio.mp3"
        allow(agent).to receive(:audio_transcription_agent).and_return(
          "ERROR: Failed to transcribe audio"
        )

        result = agent.analyze_video(file: "test.mp4")

        expect(result).to include("Video description")
        expect(result).to include("Audio transcription failed:")
      end
    end
  end

  describe '#balance_frames' do
    it 'evenly samples frames when over limit' do
      frames = (1..10).map(&:to_s)
      result = agent.send(:balance_frames, frames, 5)

      expect(result.size).to eq(5)
      expect(result.first).to eq("1")
      expect(result.last).to eq("10")
    end

    it 'handles single-frame edge case' do
      frames = ["1"]
      # balance_frames with max_frames=1 should return the single frame
      result = agent.send(:balance_frames, frames, 1)

      expect(result.size).to eq(1)
      expect(result.first).to eq("1")
    end
  end

  describe '#read_frames_json' do
    it 'strips data URL prefixes from frames' do
      frames_with_prefix = [
        "data:image/png;base64,iVBORw0KGgo=",
        "iVBORw0KGgo="
      ]
      allow(File).to receive(:exist?).and_call_original
      allow(File).to receive(:exist?).with("/test/frames.json").and_return(true)
      allow(File).to receive(:read).with("/test/frames.json").and_return(JSON.generate(frames_with_prefix))

      result = agent.send(:read_frames_json, "/test/frames.json")

      expect(result).to eq(["iVBORw0KGgo=", "iVBORw0KGgo="])
    end

    it 'returns error for invalid JSON' do
      allow(File).to receive(:exist?).and_call_original
      allow(File).to receive(:exist?).with("/test/frames.json").and_return(true)
      allow(File).to receive(:read).with("/test/frames.json").and_return("not json")

      result = agent.send(:read_frames_json, "/test/frames.json")

      expect(result).to start_with("ERROR: Failed to parse frames JSON")
    end
  end

  describe '#video_vision_query' do
    before do
      allow(File).to receive(:exist?).and_call_original
    end

    it 'resolves the video capability without using the image resolver' do
      allow(Monadic::Utils::ProviderCapabilities).to receive(:resolve).and_call_original
      expect(agent).not_to receive(:resolve_vision_provider)
      allow(agent).to receive(:video_vision_openai).and_return("Description")

      result = agent.send(:video_vision_query, "What happens?", sample_frames)

      expect(result).to eq("Description")
      expect(Monadic::Utils::ProviderCapabilities).to have_received(:resolve).with(:video, "openai")
    end

    it 'applies per-provider frame limits' do
      agent.settings["provider"] = "anthropic"
      stub_const("CONFIG", {
        "ANTHROPIC_API_KEY" => "test-anthropic-key",
        "EXTRA_LOGGING" => nil
      })

      # 30 frames should be reduced to 20 for Claude
      many_frames = (1..30).map { "iVBORw0KGgo=" }
      allow(agent).to receive(:video_vision_claude).and_return("Description")

      agent.send(:video_vision_query, "What happens?", many_frames)

      # The frames passed to video_vision_claude should be limited to 20
      expect(agent).to have_received(:video_vision_claude) do |_query, frames, _model, _key|
        expect(frames.size).to eq(20)
      end
    end
  end

  let(:timed_document) do
    {
      "schema_version" => 1, "duration_ms" => 15_000, "timestamp_source" => "ffprobe_best_effort_pts",
      "frames" => [
        { "frame_id" => "f000000", "source_frame_index" => 0, "timestamp_ms" => 0,
          "image" => "AAA=", "mime_type" => "image/png", "change_score" => 1 },
        { "frame_id" => "f000123", "source_frame_index" => 123, "timestamp_ms" => 12_340,
          "image" => "BBB=", "mime_type" => "image/jpeg", "change_score" => 0.2 }
      ]
    }
  end

  def read_document(document)
    allow(File).to receive(:exist?).with("/test/frames.json").and_return(true)
    allow(File).to receive(:read).with("/test/frames.json").and_return(JSON.generate(document))
    agent.send(:read_frames_json, "/test/frames.json")
  end

  it 'loads the versioned document and restores chronological order' do
    document = timed_document.merge("frames" => timed_document["frames"].reverse)
    expect(read_document(document)).to eq(timed_document)
  end

  it 'rejects invalid, empty and duplicate timelines' do
    expect(read_document(timed_document.merge("schema_version" => 2))).to start_with("ERROR:")
    expect(read_document(timed_document.merge("frames" => []))).to start_with("ERROR:")
    frames = [timed_document["frames"].first] * 2
    expect(read_document(timed_document.merge("frames" => frames))).to start_with("ERROR:")
    expect(read_document([])).to start_with("ERROR:")
    timed_document["frames"].last["timestamp_ms"] = -1
    expect(read_document(timed_document)).to start_with("ERROR:")
  end

  %w[anthropic deepseek unknown].each do |provider|
    it "rejects #{provider} with only another provider's key before extraction" do
      agent.settings["provider"] = provider
      expect(Monadic::Shell).not_to receive(:exec)
      expect(agent).not_to receive(:video_vision_http_post)
      expect(agent.analyze_video(file: "test.mp4")).to start_with("ERROR:")
      expect(agent.send(:video_vision_query, "Describe", sample_frames)).to start_with("ERROR:")
    end
  end

  it 'returns the capability error unchanged' do
    allow(Monadic::Utils::ProviderCapabilities).to receive(:resolve).with(:video, "openai")
      .and_return(error: "ERROR: unavailable")
    expect(agent.analyze_video(file: "test.mp4")).to eq("ERROR: unavailable")
  end

  it "transcribes the audio with xAI's own speech-to-text on Grok" do
    agent.settings = { provider: "xai" }
    CONFIG["XAI_API_KEY"] = "own-test-key"
    allow(agent).to receive(:read_frames_json).and_return(timed_document)
    allow(agent).to receive(:video_vision_query).and_return("Visible event")
    expect(agent.analyze_video(file: "test.mp4")).to include("Visible event", "Hello world, this is the audio transcript.")
  end

  %w[anthropic].each do |provider|
    it "preserves video success for #{provider} without calling unsupported transcription" do
      agent.settings = { provider: provider }
      CONFIG[Monadic::Utils::ProviderCapabilities.api_key_name(provider)] = "own-test-key"
      allow(agent).to receive(:read_frames_json).and_return(timed_document)
      allow(agent).to receive(:video_vision_query).and_return("Visible event")
      expect(agent).not_to receive(:audio_transcription_agent)
      result = agent.analyze_video(file: "test.mp4")
      expect(result).to include("Visible event", "Audio transcription is not supported by this provider")
      expect(result).not_to include("failed")
    end
  end

  %w[openai anthropic google xai].each do |provider|
    it "places timestamps immediately before each image in #{provider} requests" do
      agent.settings["provider"] = provider
      CONFIG[Monadic::Utils::ProviderCapabilities.api_key_name(provider)] = "own-test-key"
      unless defined?(OpenAIHelper)
        stub_const("OpenAIHelper", Module.new)
        OpenAIHelper.const_set(:OUTPUT_TOKEN_KEY, :max_completion_tokens)
      end
      response = double(status: double(success?: true), body: JSON.generate({
        choices: [{ message: { content: "Description" } }], content: [{ text: "Description" }],
        candidates: [{ content: { parts: [{ text: "Description" }] } }]
      }))
      expect(agent).to receive(:video_vision_http_post) do |uri, _headers, body|
        host = { "openai" => "api.openai.com", "anthropic" => "api.anthropic.com",
                 "google" => "generativelanguage.googleapis.com", "xai" => "api.x.ai" }.fetch(provider)
        expect(uri).to include(host)
        parts = provider == "google" ? body[:contents][0][:parts] : body[:messages][0][:content]
        expect(parts[0][:text]).to include("Video duration: 00:15.", "non-uniform excerpts", "Do not infer")
        # The model is told it sees frames only, so it does not report missing
        # audio next to the transcript that is appended separately.
        expect(parts[0][:text]).to include("still frames", "transcribed separately", "do not say that audio is missing")
        expect(parts[1][:text]).to eq("Frame f000000, video time 00:00")
        expect(parts[3][:text]).to eq("Frame f000123, video time 00:12.3")
        expect(parts.size).to eq(5)
        if provider == "google"
          expect(parts[4][:inline_data]).to eq(mime_type: "image/jpeg", data: "BBB=")
        elsif provider == "anthropic"
          expect(parts[4][:source]).to include(media_type: "image/jpeg", data: "BBB=")
        else
          expect(parts[4][:image_url][:url]).to eq("data:image/jpeg;base64,BBB=")
        end
        response
      end
      expect(agent.send(:video_vision_query, "Describe", timed_document)).to eq("Description")
    end
  end

  it 'does not invent timestamps for legacy arrays' do
    expect(agent).to receive(:video_vision_openai) do |query, frames, _model, _key|
      expect(query).to include("unknown timestamps")
      expect(frames).to eq(sample_frames)
      "Description"
    end
    agent.send(:video_vision_query, "Describe", sample_frames)
  end

  it 'keeps endpoints, time coverage and a brief change within the frame budget' do
    frames = (0...100).map do |i|
      { "timestamp_ms" => i * 1000, "change_score" => i == 43 ? 1.0 : 0.0 }
    end
    selected = agent.send(:balance_frames, frames.reverse, 10)
    expect(selected.size).to eq(10)
    expect(selected.first).to eq(frames.first)
    expect(selected.last).to eq(frames.last)
    expect(selected).to include(frames[43])
    expect(selected.map { |f| f["timestamp_ms"] }).to eq(selected.map { |f| f["timestamp_ms"] }.sort)
  end

  it 'hands a file name with shell syntax over as one argument, with the provider frame budget' do
    filename = 'clip $(touch should-not-exist); "quoted".mp4'
    agent.settings["provider"] = "anthropic"
    CONFIG["ANTHROPIC_API_KEY"] = "own-test-key"
    agent.extractor_output = "No frames"
    agent.analyze_video(file: filename)
    argv = extractor_calls.first[:argv]
    expect(argv[2]).to eq("/monadic/data/#{filename}")
    expect(argv[argv.index("--frames") + 1]).to eq("20")
  end

  it 'formats hour-long timestamps without wrapping minutes' do
    expect(agent.send(:video_timestamp, 3_723_456)).to eq("1:02:03.5")
    expect(agent.send(:video_timestamp, 65_000)).to eq("01:05")
    expect(agent.send(:video_timestamp, 64_970)).to eq("01:05")
    expect(agent.send(:video_clock, 3599)).to eq("59:59")
  end


  # A video attached to the chat: resolved through the ledger, run in a job
  # folder of its own, output found in that folder.
  describe 'analyzing an attachment' do
    around do |example|
      Dir.mktmpdir('video-attachment') do |dir|
        @data = File.join(dir, 'data')
        @state = File.join(dir, 'state')
        FileUtils.mkdir_p(@data)
        example.run
      end
    end

    let(:ledger) { Monadic::Workspace::Ledger.new(File.join(@state, 'ledger.json')) }
    let(:chat_id) { Monadic::Workspace::Ids.generate(:chat) }
    let(:mp4) { "\x00\x00\x00\x18ftypmp42\x00\x00\x00\x00mp42isom".b + ('x' * 2000) }
    let(:calls) { [] }
    let(:transcribed) { [] }
    let(:probe_answer) do
      { 'streams' => [{ 'codec_type' => 'video', 'codec_name' => 'h264', 'width' => 640, 'height' => 360, 'disposition' => { 'attached_pic' => 0 } },
                      { 'codec_type' => 'audio', 'codec_name' => 'aac' }],
        'format' => { 'format_name' => 'mov,mp4,m4a,3gp,3g2,mj2', 'duration' => '120.0' } }
    end
    let(:frames_json) do
      { 'schema_version' => 1, 'duration_ms' => 3000, 'timestamp_source' => 'container',
        'frames' => [{ 'frame_id' => 'f0', 'source_frame_index' => 0, 'timestamp_ms' => 0,
                       'image' => 'iVBORw0KGgo=', 'mime_type' => 'image/png' }] }
    end

    before do
      allow(Monadic::Utils::Environment).to receive(:data_path).and_return(@data)
      allow(Monadic::Utils::Environment).to receive(:state_path).and_return(@state)
      allow(Monadic::Workspace::Ledger).to receive(:default).and_return(ledger)
      allow(Monadic::Utils::SharedPathGuard).to receive(:command_path).and_call_original
      allow(Monadic::Utils::VideoProbe).to receive(:check!).and_call_original
      allow(agent).to receive(:video_vision_openai).and_return('A deer crosses the road.')
      allow(agent).to receive(:audio_transcription_agent) { |audio_path:, **| transcribed << audio_path; 'Hello.' }
      # The extractor in the Python container, played here: it writes into
      # the folder it is given, as the real script does.
      allow(Monadic::Shell).to receive(:exec) do |container:, argv:, **opts|
        next [probe_answer.to_json, '', double(success?: true)] if argv.first == 'ffprobe'
        next segmenter.call(container, argv, opts) if argv[1] == VideoAnalyzeAgent::SEGMENT_SCRIPT

        calls << { container: container, argv: argv, timeout: opts[:timeout] }
        out = File.join(File.realpath(@data), argv[3].delete_prefix('/monadic/data/'))
        File.write(File.join(out, 'frames_20261009_120000_000001.json'), frames_json.to_json)
        File.write(File.join(out, 'audio_20261009_120000.mp3'), 'ID3')
        ["Base64-encoded frames saved to /monadic/data/elsewhere.json\n", '', double(success?: true)]
      end
    end

    # speech_segments.py; by default the Python image predates it.
    let(:segmenter) do
      lambda do |_container, _argv, _opts|
        ['', "python: can't open file '#{VideoAnalyzeAgent::SEGMENT_SCRIPT}': [Errno 2]\n", double(success?: false)]
      end
    end

    def attach(chat: chat_id)
      Monadic::Workspace::Attachments.accept!(chat_id: chat, app_name: 'VideoDescriberOpenAI', purpose: 'video',
                                              original_name: 'clip.mp4', source: StringIO.new(mp4), ledger: ledger)
    end

    it 'runs the extractor without a shell on the attached file, into a job folder, and reads what it wrote there' do
      record = attach
      result = agent.analyze_video(attachment_id: record[:attachment_id], session: { chat_id: chat_id })

      expect(result).to include('A deer crosses the road.')
      expect(result).to include('Hello.')
      call = calls.first
      expect(call[:container]).to eq(:python)
      expect(call[:argv].first(2)).to eq(['python', VideoAnalyzeAgent::EXTRACT_SCRIPT])
      expect(call[:argv][2]).to eq("/monadic/data/#{record[:relative_path]}")
      expect(call[:argv][3]).to match(%r{\A/monadic/data/conversations/[^/]+/artifacts/j_[a-z0-9]{16}\z})
      expect(call[:timeout]).to eq(VideoAnalyzeAgent::VIDEO_EXTRACT_TIMEOUT)
      # The printed path is ignored; the audio is the one in the job folder.
      expect(transcribed.first).to start_with(File.join(File.realpath(@data), call[:argv][3].delete_prefix('/monadic/data/')))
    end

    it 'gives each run its own folder' do
      record = attach
      2.times { agent.analyze_video(attachment_id: record[:attachment_id], session: { chat_id: chat_id }) }
      expect(calls.map { |c| c[:argv][3] }.uniq.size).to eq(2)
    end

    it "refuses another chat's attachment before running anything" do
      record = attach(chat: Monadic::Workspace::Ids.generate(:chat))
      result = agent.analyze_video(attachment_id: record[:attachment_id], session: { chat_id: chat_id })
      expect(result).to start_with('Error: No such attachment')
      expect(calls).to be_empty
    end

    it 'refuses without a session to say which chat it is' do
      record = attach
      expect(agent.analyze_video(attachment_id: record[:attachment_id])).to start_with('Error: No such attachment')
      expect(calls).to be_empty
    end

    it 'reports a run that produced no frames' do
      allow(Monadic::Shell).to receive(:exec) do |argv:, **|
        next [probe_answer.to_json, '', double(success?: true)] if argv.first == 'ffprobe'

        ['', "cv2.error: cannot open\n", double(success?: false)]
      end
      record = attach
      result = agent.analyze_video(attachment_id: record[:attachment_id], session: { chat_id: chat_id })
      expect(result).to start_with('Error: Failed to extract frames from the video. cv2.error: cannot open')
    end

    it 'asks for mono audio at a constant bitrate' do
      record = attach
      agent.analyze_video(attachment_id: record[:attachment_id], session: { chat_id: chat_id })
      expect(calls.first[:argv]).to include('--audio', '--audio-bitrate', '64k', '--audio-channels', '1')
    end

    it 'checks the video before decoding it, and stops when the check fails' do
      probe_answer['format']['duration'] = '3601.5'
      record = attach
      result = agent.analyze_video(attachment_id: record[:attachment_id], session: { chat_id: chat_id })
      expect(result).to eq('Error: The video is 61 minutes long; videos up to 50 minutes can be analyzed.')
      expect(calls).to be_empty
    end

    it 'says to rebuild the Python container when its extractor is too old for the audio options' do
      allow(Monadic::Shell).to receive(:exec) do |argv:, **|
        if argv.first == 'ffprobe'
          [probe_answer.to_json, '', double(success?: true)]
        else
          ['', "extract_frames.py: error: unrecognized arguments: --audio-bitrate 64k --audio-channels 1\n", double(success?: false)]
        end
      end
      record = attach
      result = agent.analyze_video(attachment_id: record[:attachment_id], session: { chat_id: chat_id })
      expect(result).to include('Rebuild it (Actions > Build Python Container)')
    end

    describe 'with a timed transcript' do
      let(:segments_doc) do
        { 'schema' => 'speech-segments', 'schema_version' => 1, 'sample_rate_hz' => 24_000,
          'timebase' => 'video_relative_samples', 'status' => 'complete',
          'segments' => [{ 'segment_id' => 'seg000001', 'start_sample' => 24_000, 'end_sample' => 72_000 },
                         { 'segment_id' => 'seg000002', 'start_sample' => 1_464_000, 'end_sample' => 1_500_000 }] }
      end
      let(:segment_calls) { [] }
      let(:segmenter) do
        lambda do |container, argv, opts|
          segment_calls << { container: container, argv: argv, timeout: opts[:timeout] }
          out = File.join(File.realpath(@data), argv[3].delete_prefix('/monadic/data/'))
          File.write(File.join(out, 'segments.json'), segments_doc.to_json)
          File.binwrite(File.join(out, 'audio_24k.pcm'), "\0" * 3_000_000)
          ["Speech segments written\n", '', double(success?: true)]
        end
      end
      let(:transcriber_args) { {} }
      let(:transcript) do
        segments_doc.merge('schema' => 'timed-transcript', 'status' => 'complete',
                           'segments' => [segments_doc['segments'][0].merge('status' => 'complete', 'text' => 'Hello there.'),
                                          segments_doc['segments'][1].merge('status' => 'complete', 'text' => 'Goodbye.')])
      end

      before do
        allow(Monadic::Utils::SegmentTranscriber).to receive(:new) do |**args|
          transcriber_args.merge!(args)
          double(run: transcript)
        end
      end

      def analyze(session = { chat_id: chat_id })
        agent.analyze_video(attachment_id: attach[:attachment_id], session: session)
      end

      it 'puts the video time of each segment before its text, and does not use the untimed transcription' do
        result = analyze
        expect(result).to include("Audio Transcript:\n[00:01–00:03] Hello there.\n[01:01–01:03] Goodbye.")
        expect(transcribed).to be_empty
        expect(transcriber_args[:model]).to eq('gpt-transcribe')
      end

      it 'finds speech in the attached file, in the same run folder, and keeps the transcript there' do
        analyze
        call = segment_calls.first
        expect(call[:container]).to eq(:python)
        expect(call[:argv].first(3)).to eq(['python', VideoAnalyzeAgent::SEGMENT_SCRIPT, calls.first[:argv][2]])
        expect(call[:argv][3]).to eq(calls.first[:argv][3])
        job = File.join(File.realpath(@data), call[:argv][3].delete_prefix('/monadic/data/'))
        expect(JSON.parse(File.read(File.join(job, 'transcript.json')))['segments'].map { |s| s['text'] })
          .to eq(['Hello there.', 'Goodbye.'])
        expect(File.exist?(File.join(job, 'audio_24k.pcm'))).to be(false)
        expect(transcriber_args[:pcm_path]).to eq(File.join(job, 'audio_24k.pcm'))
      end

      it 'stops sending when the chat changes' do
        session = { chat_id: chat_id }
        analyze(session)
        expect(transcriber_args[:cancelled].call).to be(false)
        session[:chat_id] = Monadic::Workspace::Ids.generate(:chat)
        expect(transcriber_args[:cancelled].call).to be(true)
      end

      it 'says when the chat changed before every segment was sent' do
        transcript['status'] = 'cancelled'
        transcript['segments'][1]['status'] = 'pending'
        result = analyze
        expect(result).to include('[00:01–00:03] Hello there.')
        expect(result).not_to include('Goodbye.')
        expect(result).not_to include('transcription failed')
        expect(result).to include('(Stopped because the chat changed.)')
      end

      it 'marks segments that could not be transcribed, and says so once when none could' do
        transcript['status'] = 'partial'
        transcript['segments'][1].merge!('status' => 'failed', 'error' => 'timeout', 'text' => nil)
        expect(analyze).to include("[01:01–01:03] (transcription failed)\n(Some segments could not be transcribed.)")

        transcript['status'] = 'failed'
        transcript['segments'].each { |s| s.merge!('status' => 'failed', 'error' => 'protocol: session rejected (invalid_api_key)') }
        result = analyze
        expect(result).to include("Audio Transcript:\nAudio transcription failed: protocol: session rejected (invalid_api_key).")
        expect(result.scan('transcription failed').size).to eq(1)
      end

      it 'leaves out segments that came back without words' do
        transcript['segments'][0]['text'] = '  '
        result = analyze
        expect(result).to include("Audio Transcript:\n[01:01–01:03] Goodbye.")
        expect(result).not_to include('00:01–00:03')
      end

      it 'says there is no speech without opening a transcription session' do
        segments_doc.merge!('status' => 'no_speech_detected', 'segments' => [])
        expect(analyze).to include("Audio Transcript:\n(No speech was detected in the audio.)")
        expect(Monadic::Utils::SegmentTranscriber).not_to have_received(:new)
      end

      context 'when the Python image is too old' do
        let(:segmenter) do
          ->(*) { ['', "ModuleNotFoundError: No module named 'onnxruntime'\n", double(success?: false)] }
        end

        it 'falls back to the untimed transcription, saying why' do
          result = analyze
          expect(result).to include('Hello.')
          expect(result).to include(VideoAnalyzeAgent::UNTIMED_NOTE)
          expect(Monadic::Utils::SegmentTranscriber).not_to have_received(:new)
        end
      end

      it 'gives a video named from the shared folder a run folder in the chat, and none without a chat' do
        timed = agent.send(:timed_transcript, { input: '/monadic/data/clip.mp4' }, 'openai', { chat_id: chat_id })
        expect(timed[:text]).to include('[00:01–00:03] Hello there.')
        call = segment_calls.first
        expect(call[:argv][2]).to eq('/monadic/data/clip.mp4')
        expect(call[:argv][3]).to match(%r{\A/monadic/data/conversations/[^/]+/artifacts/j_[a-z0-9]{16}\z})
        expect(ledger.workspace_for_chat(chat_id)).not_to be_nil

        expect(agent.send(:timed_transcript, { input: '/monadic/data/clip.mp4' }, 'openai', nil)).to be_nil
        expect(segment_calls.size).to eq(1)
      end

      it 'is not used for a provider without its own speech-to-text' do
        expect(agent.send(:timed_transcript, { job: { path: @data } }, 'anthropic', { chat_id: chat_id })).to be_nil
        expect(segment_calls).to be_empty
      end

      %w[google xai].each do |provider|
        it "sends each segment to #{provider}'s own speech-to-text, a request per segment" do
          CONFIG[AudioTranscriptionAgent::AUDIO_API_KEYS[provider]] = 'own-test-key'
          batch_args = {}
          allow(Monadic::Utils::SegmentTranscriber::Batch).to receive(:new) do |**args|
            batch_args.merge!(args)
            double(run: transcript)
          end
          allow(agent).to receive(:transcribe_audio_bytes).and_return('segment text')
          timed = agent.send(:timed_transcript, { input: '/monadic/data/clip.mp4' }, provider, { chat_id: chat_id })

          expect(timed[:text]).to include('[00:01–00:03] Hello there.')
          expect(Monadic::Utils::SegmentTranscriber).not_to have_received(:new)
          expect(batch_args[:model]).to eq(AudioTranscriptionAgent.audio_model_for(provider))
          expect(batch_args[:transcribe].call('RIFF')).to eq('segment text')
          expect(agent).to have_received(:transcribe_audio_bytes).with(provider, 'RIFF', 'wav', batch_args[:model])
        end
      end

      it 'keeps the untimed transcription when no model can transcribe committed segments' do
        allow(Monadic::Utils::ModelSpec).to receive(:supports_segment_transcription?).and_return(false)
        result = analyze
        expect(result).to include('Hello.')
        expect(result).not_to include(VideoAnalyzeAgent::UNTIMED_NOTE)
        expect(segment_calls).to be_empty
      end
    end

    it 'reports a run that took too long' do
      allow(Monadic::Shell).to receive(:exec) do |argv:, **|
        raise Monadic::Shell::TimedOut unless argv.first == 'ffprobe'

        [probe_answer.to_json, '', double(success?: true)]
      end
      record = attach
      result = agent.analyze_video(attachment_id: record[:attachment_id], session: { chat_id: chat_id })
      expect(result).to include('took longer than 15 minutes')
    end
  end
end
