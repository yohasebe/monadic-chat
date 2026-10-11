# frozen_string_literal: true

require "spec_helper"
require "json"
require "open3"
require "tmpdir"
require "rbconfig"

# A video attached in the chat, end to end through the real app: a tab opens
# its WebSocket, uploads to /attachments with its tab id, and Video Describer
# analyzes the attachment. Booted from config.ru in a child process with its
# own HOME, over real sockets. Only what needs Docker or a provider is played
# here: the commands sent to the Python container, the vision call and the
# transcription.
RSpec.describe "Attaching a video and analyzing it" do
  def app_root
    File.expand_path("../../..", __dir__)
  end

  def probe_script
    <<~'RUBY'
    require "rack"
    require "json"
    require "socket"
    require "async"
    require "async/http/endpoint"
    require "async/http/server"
    require "async/http/client"
    require "async/websocket/client"
    require "protocol/rack"
    require "protocol/http/body/buffered"
    app, = Rack::Builder.parse_file("config.ru")
    data = File.join(Dir.home, "monadic", "data")
    out = {}

    # What the Python container would do: report the video, extract frames
    # and audio into the folder it is given, and (an older image) lack the
    # speech segmenter, so the untimed transcription is used.
    probe_answer = { "streams" => [{ "codec_type" => "video", "codec_name" => "h264", "width" => 640, "height" => 360,
                                     "disposition" => { "attached_pic" => 0 } }, { "codec_type" => "audio", "codec_name" => "aac" }],
                     "format" => { "format_name" => "mov,mp4,m4a,3gp,3g2,mj2", "duration" => "12.0" } }.to_json
    frames = { "schema_version" => 1, "duration_ms" => 12_000, "timestamp_source" => "container",
               "frames" => [{ "frame_id" => "f0", "source_frame_index" => 0, "timestamp_ms" => 0, "image" => "iVBORw0KGgo=", "mime_type" => "image/png" }] }
    ok = Struct.new(:success?).new(true)
    failed = Struct.new(:success?).new(false)
    Monadic::Shell.define_singleton_method(:exec) do |container:, argv:, **|
      next [probe_answer, "", ok] if argv.first == "ffprobe"
      next ["", "python: can't open file '#{argv[1]}': [Errno 2]", failed] if argv[1].to_s.end_with?("speech_segments.py")

      dir = File.join(File.realpath(data), argv[3].delete_prefix("/monadic/data/"))
      File.write(File.join(dir, "frames_20261010_000000_000001.json"), frames.to_json)
      File.binwrite(File.join(dir, "audio_20261010_000000.mp3"), "ID3")
      ["frames saved", "", ok]
    end

    mp4 = "\x00\x00\x00\x18ftypmp42\x00\x00\x00\x00mp42isom".b + ("x" * 4000)
    port = (probe = TCPServer.new("127.0.0.1", 0)).addr[1]
    probe.close
    base = "http://127.0.0.1:#{port}"
    endpoint = Async::HTTP::Endpoint.parse(base)
    Async do |task|
      server = task.async { Async::HTTP::Server.new(Protocol::Rack::Adapter.new(app), endpoint).run }
      task.sleep(0.2)
      client = Async::HTTP::Client.new(endpoint)
      upload = lambda do |tab, body: mp4, name: "clip.mp4"|
        boundary = "B#{rand(1_000_000)}"
        payload = "--#{boundary}\r\nContent-Disposition: form-data; name=\"purpose\"\r\n\r\nvideo\r\n" \
                  "--#{boundary}\r\nContent-Disposition: form-data; name=\"file\"; filename=\"#{name}\"\r\n" \
                  "Content-Type: video/mp4\r\n\r\n".b + body + "\r\n--#{boundary}--\r\n".b
        headers = [["content-type", "multipart/form-data; boundary=#{boundary}"], ["origin", base]]
        response = client.post("/attachments?tab_id=#{tab}", headers, Protocol::HTTP::Body::Buffered.wrap(payload))
        [response.status, (JSON.parse(response.read) rescue {})]
      end
      open_tab = lambda do |tab|
        ws = Async::WebSocket::Client.connect(Async::HTTP::Endpoint.parse("#{base}/?tab_id=#{tab}"), headers: [["origin", base]])
        task.with_timeout(10) { ws.read } # the first message: the tab is registered
        ws
      end
      chat_of = ->(tab) { WebSocketHelper.fetch_session_state(tab)&.dig(:chat_id) }
      usable = lambda do |chat, id|
        Monadic::Workspace::Attachments.resolve!(chat_id: chat, attachment_id: id)
        "usable"
      rescue Monadic::Workspace::Attachments::Unusable => e
        "refused:#{e.reason}"
      end

      tab_a = open_tab.call("tab-a")
      status, body = upload.call("tab-a")
      id = body["attachment_id"]
      chat_a = chat_of.call("tab-a")
      out["upload"] = { "status" => status, "has_id" => Monadic::Workspace::Ids.valid?(:attachment, id), "name" => body["name"] }
      record = Monadic::Workspace::Ledger.default.attachment(id)
      out["stored_in_chat_folder"] = record && File.file?(File.join(data, record[:relative_path])) &&
                                     record[:relative_path].start_with?("conversations/") && record[:relative_path].include?("/inputs/")
      out["usable_in_its_chat"] = usable.call(chat_a, id)

      # Video Describer as the model would call it, with the id in `file`.
      describer = APPS["VideoDescriberApp"]
      describer.define_singleton_method(:video_vision_query) { |*_args, **_kw| "A deer crosses the road." }
      describer.define_singleton_method(:audio_transcription_agent) { |**_kw| "Hello." }
      result = describer.analyze_video(file: id, fps: 1, session: { chat_id: chat_a, parameters: {} })
      out["analysis_head"] = result.lines.first.to_s.strip
      out["analysis_has_description"] = result.include?("A deer crosses the road.")
      pub = File.join(data, "pub_#{id}.mp4")
      out["public_copy_matches"] = File.file?(pub) && File.binread(pub) == mp4

      tab_b = open_tab.call("tab-b")
      out["other_tab"] = usable.call(chat_of.call("tab-b"), id)

      tab_a.write({ "message" => "RESET" }.to_json)
      tab_a.flush
      task.sleep(0.3)
      out["chat_changed_on_reset"] = chat_of.call("tab-a") != chat_a
      out["after_reset"] = usable.call(chat_of.call("tab-a"), id)
      out["after_reset_old_chat"] = usable.call(chat_a, id)

      status, = upload.call("no-such-tab")
      out["unknown_tab"] = status
      status, body = upload.call("tab-a", body: "not a video", name: "notes.mp4")
      out["not_a_video"] = [status, body["reason"]]

      [tab_a, tab_b].each(&:close)
      client.close
      server.stop
    end
    STDOUT.puts "PROBE #{out.to_json}"
    STDOUT.flush
    exit!(0)
    RUBY
  end

  def probe
    Dir.mktmpdir("attachment-flow-home") do |home|
      tmp = File.join(home, "tmp")
      Dir.mkdir(tmp)
      FileUtils.mkdir_p(File.join(home, "monadic", "data"))
      # The app reads keys from its config file; this one is never sent anywhere
      # (the provider calls are played in the probe).
      FileUtils.mkdir_p(File.join(home, "monadic", "config"))
      File.write(File.join(home, "monadic", "config", "env"), "OPENAI_API_KEY=sk-test-not-used\n")
      # Only what Ruby and Bundler need is passed on: no key or setting of
      # this shell reaches the app.
      kept = ENV.to_h.select { |k, _| k == "PATH" || k == "LANG" || k.start_with?("BUNDLE", "GEM_", "RUBY", "RBENV") }
      env = kept.merge("HOME" => home, "IN_CONTAINER" => "false", "TMPDIR" => tmp)
      out, status = Open3.capture2e(env, RbConfig.ruby, "-e", probe_script, chdir: app_root, unsetenv_others: true)
      line = out.lines.find { |l| l.start_with?("PROBE ") }
      raise "probe failed (#{status.exitstatus}):\n#{out.lines.last(25).join}" unless line

      JSON.parse(line.delete_prefix("PROBE "))
    end
  end

  before(:all) { @result = probe }

  it "takes the upload of a connected tab into that tab's chat folder" do
    expect(@result["upload"]).to eq("status" => 201, "has_id" => true, "name" => "clip.mp4")
    expect(@result["stored_in_chat_folder"]).to be(true)
    expect(@result["usable_in_its_chat"]).to eq("usable")
  end

  it "analyzes the attachment even when the model passes its id as the file name, and publishes a copy to play" do
    expect(@result["analysis_head"]).to match(%r{\AVideo for display: /data/pub_a_[a-z0-9]{16}\.mp4\z})
    expect(@result["analysis_has_description"]).to be(true)
    expect(@result["public_copy_matches"]).to be(true)
  end

  it "keeps an attachment to its chat: not another tab's, and not after Reset" do
    expect(@result["other_tab"]).to start_with("refused:")
    expect(@result["chat_changed_on_reset"]).to be(true)
    expect(@result["after_reset"]).to start_with("refused:")
    expect(@result["after_reset_old_chat"]).to eq("usable")
  end

  it "refuses an upload from an unknown tab, and a file that is not a video" do
    expect(@result["unknown_tab"]).to eq(409)
    expect(@result["not_a_video"].first).to eq(415)
  end
end
