# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require_relative "../../../lib/monadic/utils/gemini_omni_video"

# Gemini Omni video generation over the Interactions API, with the HTTP
# transport stubbed: the request each case sends, and how each reply or
# failure is reported. Paid generation is sent once and never again.
RSpec.describe Monadic::Utils::GeminiOmniVideo, :no_api do
  let(:mp4) { "\x00\x00\x00\x18ftypmp42".b + ("x" * 64) }
  let(:chain) { double("http chain") }
  let(:posts) { [] }
  let(:gets) { [] }
  let(:headers_sent) { [] }

  around do |example|
    Dir.mktmpdir("omni-") do |dir|
      @dir = dir
      example.run
    end
  end

  def generator(deadline: 600)
    described_class.new(api_key: "k", model: "gemini-omni-1.1-flash", save_dir: @dir, deadline_seconds: deadline)
  end

  def reply(code, body, headers: {})
    double("response", status: double(success?: code < 400, code: code), headers: headers,
                       body: body.is_a?(String) ? body : body.to_json)
  end

  def completed(content)
    { "status" => "completed", "steps" => [{ "type" => "thought" }, { "type" => "model_output", "content" => [content] }] }
  end

  # Every request goes through HttpClient.deadline; nothing else reaches the
  # network from these examples.
  before do
    %i[rest generation streaming download].each do |m|
      allow(Monadic::Utils::HttpClient).to receive(m).and_raise("unstubbed HttpClient.#{m}")
    end
    allow(HTTP).to receive(:timeout).and_raise("unstubbed HTTP.timeout")
  end

  def stub_transport(post_reply: nil, post_error: nil, get_reply: nil)
    allow(Monadic::Utils::HttpClient).to receive(:deadline).and_return(chain)
    allow(chain).to receive(:headers) { |h| headers_sent << h; chain }
    allow(chain).to receive(:follow).and_return(chain)
    allow(chain).to receive(:post) do |url, json:|
      posts << [url, json]
      raise post_error if post_error

      post_reply
    end
    allow(chain).to receive(:get) { |url| gets << url; get_reply }
  end

  describe "the request" do
    before { stub_transport(post_reply: reply(200, completed({ "type" => "video", "data" => Base64.strict_encode64(mp4) }))) }

    it "asks for one stateless, synchronous text-to-video at 720p and the given length" do
      generator.generate(prompt: "a paper boat", aspect_ratio: "9:16", duration: 5)
      url, body = posts.first
      expect(url).to eq(described_class::ENDPOINT)
      expect(body).to include(model: "gemini-omni-1.1-flash", input: "a paper boat", store: false, background: false, stream: false)
      expect(body[:response_format]).to eq(type: "video", aspect_ratio: "9:16", resolution: "720p", duration: "5s")
      expect(headers_sent.first).to include("x-goog-api-key" => "k")
    end

    it "sends an image as the first frame, and what to avoid in the prompt" do
      generator.generate(prompt: "it drifts away", image: { data: "IMG", mime_type: "image/jpeg" }, negative_prompt: "people")
      body = posts.first[1]
      expect(body[:input][0]).to eq(type: "image", data: Base64.strict_encode64("IMG"), mime_type: "image/jpeg")
      expect(body[:input][1][:text]).to start_with("<FIRST_FRAME>").and include("it drifts away", "Avoid: people")
      expect(body[:generation_config]).to eq(video_config: { task: "image_to_video" })
      expect(body[:response_format][:duration]).to eq("8s")
    end

    it "refuses what the model would refuse, before any request" do
      [{ prompt: " " }, { prompt: "x", duration: 11 }, { prompt: "x", duration: 2 }, { prompt: "x", duration: "4.5" },
       { prompt: "x", aspect_ratio: "4:3" }, { prompt: "x", image: { data: "x", mime_type: "image/gif" } }].each do |args|
        result = generator.generate(**args)
        expect(result).to include(success: false, error: "invalid_input")
      end
      expect(posts).to be_empty
    end
  end

  describe "a completed reply" do
    it "saves the video under a new name and reports it" do
      stub_transport(post_reply: reply(200, completed({ "type" => "video", "data" => Base64.strict_encode64(mp4) })))
      result = generator.generate(prompt: "a boat")
      expect(result).to include(success: true, model: "gemini-omni-1.1-flash", duration: 8, resolution: "720p", mode: "text_to_video")
      expect(result[:filename]).to match(/\Agemini_omni_\d{8}_\d{6}_[0-9a-f]{8}\.mp4\z/)
      expect(File.binread(File.join(@dir, result[:filename]))).to eq(mp4)
      expect(Dir.children(@dir)).to eq([result[:filename]]) # no partial file left
    end

    it "downloads a video given as an address on Google's API host, with the key" do
      uri = "https://generativelanguage.googleapis.com/v1beta/files/abc:download?alt=media"
      stub_transport(post_reply: reply(200, completed({ "type" => "video", "uri" => uri })))
      answers = [reply(200, { "state" => "ACTIVE" }), reply(200, mp4)]
      allow(chain).to receive(:get) { |url| gets << url; answers.shift }
      expect(generator.generate(prompt: "a boat")[:success]).to be true
      expect(gets).to eq(["https://generativelanguage.googleapis.com/v1beta/files/abc", uri])
      expect(headers_sent.last).to eq("x-goog-api-key" => "k")
    end

    it "never sends the key to an address elsewhere" do
      stub_transport(post_reply: reply(200, completed({ "type" => "video", "uri" => "https://storage.example.com/v.mp4" })))
      expect(generator.generate(prompt: "a boat")).to include(success: false, error: "invalid_reply")
      expect(gets).to be_empty
    end

    it "calls a reply without a usable MP4 a failure, and saves nothing" do
      [completed({ "type" => "text", "text" => "no" }),
       completed({ "type" => "video", "data" => "%%%" }),
       completed({ "type" => "video", "data" => Base64.strict_encode64("not a video at all") })].each do |body|
        stub_transport(post_reply: reply(200, body))
        expect(generator.generate(prompt: "a boat")[:success]).to be false
      end
      expect(Dir.children(@dir)).to be_empty
    end
  end

  describe "saving" do
    before { stub_transport(post_reply: reply(200, completed({ "type" => "video", "data" => Base64.strict_encode64(mp4) }))) }

    it "never replaces a file already published under the name it drew" do
      allow(SecureRandom).to receive(:hex).and_return("aaaaaaaa", "bbbbbbbb")
      allow(Time).to receive(:now).and_return(Time.new(2026, 10, 17, 12, 0, 0))
      taken = File.join(@dir, "gemini_omni_20261017_120000_aaaaaaaa.mp4")
      File.write(taken, "someone else's video")
      result = generator.generate(prompt: "a boat")
      expect(result[:filename]).to eq("gemini_omni_20261017_120000_bbbbbbbb.mp4")
      expect(File.read(taken)).to eq("someone else's video")
    end

    it "does not save where hard links are not available, rather than risk replacing a file" do
      allow(File).to receive(:link).and_raise(Errno::ENOTSUP)
      result = generator.generate(prompt: "a boat")
      expect(result).to include(success: false, error: "save_failed")
      expect(result[:message]).to include("does not support hard links")
      expect(Dir.children(@dir)).to be_empty
    end

    it "removes its own partial file when writing it fails" do
      real_open = File.method(:open)
      allow(File).to receive(:open) do |path, *args, &block|
        next real_open.call(path, *args, &block) unless path.to_s.end_with?(".part")

        real_open.call(path, *args) do |f|
          f.write("half")
          allow(f).to receive(:write).and_raise(Errno::ENOSPC)
          block.call(f)
        end
      end
      result = generator.generate(prompt: "a boat")
      expect(result).to include(success: false, error: "save_failed")
      expect(Dir.children(@dir)).to be_empty
    end

    it "leaves another call's partial file alone" do
      allow(SecureRandom).to receive(:hex).and_return("cccccccc", "dddddddd")
      allow(Time).to receive(:now).and_return(Time.new(2026, 10, 17, 12, 0, 0))
      theirs = File.join(@dir, ".gemini_omni_20261017_120000_cccccccc.mp4.part")
      File.write(theirs, "in progress")
      expect(generator.generate(prompt: "a boat")[:filename]).to end_with("dddddddd.mp4")
      expect(File.read(theirs)).to eq("in progress")
    end
  end

  describe "a download that redirects" do
    let(:uri) { "https://generativelanguage.googleapis.com/v1beta/files/abc:download?alt=media" }
    let(:deadlines) { [] }

    before do
      stub_transport(post_reply: reply(200, completed({ "type" => "video", "uri" => uri })))
      allow(Monadic::Utils::HttpClient).to receive(:deadline) { |seconds| deadlines << seconds; chain }
    end

    it "follows each hop with the time left then, and sends the key only to the API host" do
      answers = [reply(200, { "state" => "ACTIVE" }),
                 reply(302, "", headers: { "Location" => "https://storage.example.com/v.mp4?sig=1" }),
                 reply(200, mp4)]
      allow(chain).to receive(:get) { |url| gets << url; answers.shift }
      expect(generator.generate(prompt: "a boat")[:success]).to be true
      expect(gets.last).to eq("https://storage.example.com/v.mp4?sig=1")
      expect(headers_sent.last).to eq({})
      expect(headers_sent[-2]).to eq("x-goog-api-key" => "k")
      expect(deadlines.size).to eq(4) # the POST, the file check and each download hop
      expect(deadlines.each_cons(2).all? { |a, b| b <= a }).to be true
    end

    it "gives each hop exactly the time left, by the clock" do
      clock = 0.0
      gen = generator(deadline: 10)
      allow(gen).to receive(:monotonic) { clock }
      gen.instance_variable_set(:@deadline, 10.0)
      answers = [reply(200, { "state" => "ACTIVE" }),
                 reply(302, "", headers: { "Location" => "../files/abc/moved" }),
                 reply(200, mp4)]
      allow(chain).to receive(:get) { |url| gets << url; clock += 1.0; answers.shift }
      allow(chain).to receive(:post) { |_url, json:| posts << json; clock += 1.0; reply(200, completed({ "type" => "video", "uri" => uri })) }
      expect(gen.generate(prompt: "a boat")[:success]).to be true
      expect(deadlines).to eq([10.0, 9.0, 8.0, 7.0])
      expect(gets.last).to eq("https://generativelanguage.googleapis.com/v1beta/files/abc/moved")
    end

    it "refuses a redirect off HTTPS and stops after a few hops" do
      answers = [reply(200, { "state" => "ACTIVE" }), reply(302, "", headers: { "Location" => "http://storage.example.com/v.mp4" })]
      allow(chain).to receive(:get) { |url| gets << url; answers.shift }
      expect(generator.generate(prompt: "a boat")).to include(success: false, error: "invalid_reply")

      hop = reply(302, "", headers: { "Location" => "https://generativelanguage.googleapis.com/v1beta/other" })
      allow(chain).to receive(:get) { |url| gets << url; url.include?("/files/abc") && !url.include?(":download") ? reply(200, { "state" => "ACTIVE" }) : hop }
      expect(generator.generate(prompt: "a boat")).to include(success: false, error: "download_failed")
    end
  end

  describe "a video given as a Files API address" do
    let(:uri) { "https://generativelanguage.googleapis.com/v1beta/files/abc:download?alt=media" }

    it "waits until the file is ACTIVE, then downloads it" do
      stub_transport(post_reply: reply(200, completed({ "type" => "video", "uri" => uri })))
      states = [reply(200, { "state" => "PROCESSING" }), reply(200, { "state" => "ACTIVE" }), reply(200, mp4)]
      allow(chain).to receive(:get) { |url| gets << url; states.shift }
      allow_any_instance_of(described_class).to receive(:sleep)
      expect(generator.generate(prompt: "a boat")[:success]).to be true
      expect(gets).to eq(["https://generativelanguage.googleapis.com/v1beta/files/abc",
                          "https://generativelanguage.googleapis.com/v1beta/files/abc", uri])
    end

    it "reports a file that failed to be prepared" do
      stub_transport(post_reply: reply(200, completed({ "type" => "video", "uri" => uri })))
      allow(chain).to receive(:get) { |url| gets << url; reply(200, { "state" => "FAILED" }) }
      result = generator.generate(prompt: "a boat")
      expect(result).to include(success: false, error: "download_failed")
      expect(gets.size).to eq(1)
    end
  end

  describe "failures" do
    it "passes on the reason of a refused request" do
      stub_transport(post_reply: reply(400, { "error" => { "message" => "Requested video duration 12s exceeds the maximum allowed 10s", "code" => "invalid_request" } }))
      result = generator.generate(prompt: "a boat")
      expect(result).to include(success: false, error: "rejected")
      expect(result[:message]).to include("HTTP 400", "maximum allowed 10s")
    end

    it "tells a provider error from a refusal" do
      stub_transport(post_reply: reply(503, { "error" => { "message" => "overloaded" } }))
      expect(generator.generate(prompt: "a boat")[:error]).to eq("provider_error")
    end

    it "reports an interaction that did not complete" do
      stub_transport(post_reply: reply(200, { "status" => "failed", "errors" => [{ "message" => "blocked by policy" }] }))
      result = generator.generate(prompt: "a boat")
      expect(result).to include(success: false, error: "not_completed")
      expect(result[:message]).to include("blocked by policy")
    end

    it "does not ask again when the reply never arrived, and says a video may have been made" do
      stub_transport(post_error: HTTP::TimeoutError.new("read timeout"))
      result = generator.generate(prompt: "a boat")
      expect(result).to include(success: false, error: "unknown_outcome")
      expect(result[:message]).to include("may still have been generated", "not requested again")
      expect(posts.size).to eq(1)
    end

    it "calls a break while the reply is being read an unknown outcome, not sent again" do
      body = double("body")
      allow(body).to receive(:readpartial).and_raise(HTTP::TimeoutError.new("read timeout"))
      stub_transport(post_reply: double("response", status: double(success?: true, code: 200), body: body))
      result = generator.generate(prompt: "a boat")
      expect(result).to include(success: false, error: "unknown_outcome")
      expect(posts.size).to eq(1)
    end

    it "sends nothing once the deadline has passed" do
      stub_transport(post_reply: reply(200, completed({ "type" => "video", "data" => Base64.strict_encode64(mp4) })))
      result = generator(deadline: -1).generate(prompt: "a boat")
      expect(result).to include(success: false, error: "deadline")
      expect(posts).to be_empty
    end

    it "keeps quoted data out of a provider's message" do
      quoted = "Invalid image data: #{Base64.strict_encode64('x' * 900)} and data:image/png;base64,#{'A' * 300}"
      stub_transport(post_reply: reply(400, { "error" => { "message" => quoted } }))
      message = generator.generate(prompt: "a boat")[:message]
      expect(message).to include("Invalid image data", "[data omitted]")
      expect(message).not_to match(%r{[A-Za-z0-9+/]{120,}})
      expect(message.length).to be < 600
    end

    it "calls a refused connection unreachable, and a connection that broke later an unknown outcome" do
      stub_transport(post_error: HTTP::ConnectionError.new("failed to connect: Connection refused - connect(2)"))
      expect(generator.generate(prompt: "a boat")[:error]).to eq("unreachable")
      stub_transport(post_error: HTTP::ConnectionError.new("error reading from socket: Connection reset by peer"))
      expect(generator.generate(prompt: "a boat")[:error]).to eq("unknown_outcome")
    end
  end
end
