# frozen_string_literal: true

require "spec_helper"
require "http"
require "base64"
require "stringio"
require_relative "../../../lib/monadic/utils/tts_utils"
require_relative "../../../lib/monadic/utils/model_spec"

RSpec.describe "Gemini TTS audio decoding" do
  let(:host) do
    Class.new do
      include InteractionUtils
    end.new
  end
  let(:script_path) { File.expand_path("../../../scripts/cli_tools/tts_query.rb", __dir__) }
  let(:script) do
    # Evaluate only definitions in an isolated receiver, without running the
    # CLI, spawning a process or installing methods/constants on Object.
    Object.new.tap do |receiver|
      receiver.instance_eval(File.read(script_path).split("# Usage:", 2).first, script_path)
    end
  end
  let(:pcm) { [0, 1, -1, 2].pack("s<*") }
  let(:wav) do
    # Independent fixture, intentionally not using the production encoder.
    ["RIFF", 36 + pcm.bytesize, "WAVE", "fmt ", 16, 1, 1,
     48000, 96000, 2, 16, "data", pcm.bytesize].pack("a4Va4a4VvvVVvva4V") + pcm
  end
  let(:client) { double("HTTP client") }
  let(:model) { "gemini-3.8-flash-tts" }

  before do
    stub_const("CONFIG", { "GEMINI_API_KEY" => "test-key" })
    %w[OPEN_TIMEOUT READ_TIMEOUT WRITE_TIMEOUT].each { |name| stub_const("InteractionUtils::#{name}", 1) }
    allow(Monadic::Utils::ExtraLogger).to receive(:log)
    allow(HTTP).to receive(:headers).and_return(client)
    allow(HTTP).to receive(:timeout).and_return(client)
    allow(client).to receive(:headers).and_return(client)
    allow(client).to receive(:timeout).and_return(client)
    allow(host).to receive(:resolve_tts_model).and_return(model)
    # Run the worker and callback synchronously; all HTTP is stubbed.
    allow(Thread).to receive(:new).and_yield
    allow(host).to receive(:Async).and_yield
    allow(File).to receive(:read).and_call_original
    ["/monadic/config/env", "#{Dir.home}/monadic/config/env"].each do |path|
      allow(File).to receive(:read).with(path).and_return("GEMINI_API_KEY=test-key\n")
    end
  end

  def respond_with(audio, mime)
    body = { candidates: [{ content: { parts: [{ inlineData: {
      data: Base64.strict_encode64(audio), mimeType: mime
    } }] } }] }.to_json
    allow(client).to receive(:post).and_return(double(body: body, status: double(success?: true)))
  end

  def request_audio(route)
    options = { provider: "gemini-flash", voice: "kore", response_format: "wav", speed: 0.8, language: "auto" }
    case route
    when :normal
      host.tts_api_request("Hello", **options)
    when :sentence
      result = nil
      host.tts_api_request_async("Hello", **options, sequence_id: 7) { |value| result = value }
      expect(result["sequence_id"]).to eq(7)
      result
    when :cli
      allow(script).to receive(:resolve_tts_model).and_return(model)
      script.tts_api_request("Hello", **options).transform_keys(&:to_s)
    end
  end

  def audio_bytes(result)
    expect(result["mime_type"]).to eq("audio/wav")
    result["audio_data"] || Base64.strict_decode64(result.fetch("content"))
  end

  [:normal, :sentence, :cli].each do |route|
    context route.to_s do
      ["audio/l16; rate=32000; channels=1", "audio/L16;codec=pcm;rate=32000", "audio/wav"].each do |mime|
        it "wraps raw PCM even with MIME #{mime}" do
          respond_with(pcm, mime)
          output = audio_bytes(request_audio(route))
          expect(output.byteslice(0, 4)).to eq("RIFF")
          expect(output.byteslice(8, 4)).to eq("WAVE")
          expect(output.byteslice(24, 4).unpack1("V")).to eq(mime == "audio/wav" ? 24000 : 32000)
          expect(output.byteslice(44..)).to eq(pcm)
          expect(output.bytesize).to eq(pcm.bytesize + 44)
        end
      end

      ["audio/wav", "audio/l16; rate=24000; channels=1", nil].each do |mime|
        it "passes WAV through byte-for-byte with MIME #{mime.inspect}" do
          respond_with(wav, mime)
          expect(audio_bytes(request_audio(route))).to eq(wav)
        end
      end

      it "preserves extra chunks and a non-default sample rate" do
        extended = wav.dup.insert(12, "JUNK" + [3].pack("V") + "abc\0")
        extended[4, 4] = [extended.bytesize - 8].pack("V")
        respond_with(extended, "audio/wav")
        expect(audio_bytes(request_audio(route))).to eq(extended)
      end

      [:short, :signature, :truncated, :missing_fmt, :short_fmt, :zero_rate, :partial_magic, :empty].each do |damage|
        it "returns an error for #{damage} WAV/audio" do
          broken = wav.dup
          case damage
          when :short then broken = "RIFF"
          when :signature then broken[8, 4] = "AVI "
          when :truncated then broken = broken.byteslice(0, broken.bytesize - 2)
          when :missing_fmt then broken[12, 4] = "JUNK"
          when :short_fmt then broken[16, 4] = [4].pack("V")
          when :zero_rate then broken[24, 4] = [0].pack("V")
          when :partial_magic then broken = "RIF"
          when :empty then broken = ""
          end
          respond_with(broken, "audio/wav")
          expect(request_audio(route)["type"]).to eq("error")
        end
      end

      it "does not prepend a pace instruction for the new default" do
        respond_with(wav, "audio/wav")
        request_audio(route)
        expect(client).to have_received(:post) do |_, json:|
          expect(json.dig("contents", 0, "parts", 0, "text")).to eq("Hello")
        end
      end
    end
  end

  [:normal, :sentence, :cli].each do |route|
    it "routes Flash-Lite audio through #{route} using its actual resolver" do
      allow(host).to receive(:resolve_tts_model).and_call_original
      respond_with(wav, "audio/wav")
      options = { provider: "gemini-flash-lite", voice: "kore", response_format: "wav", speed: 1.0, language: "auto" }
      result = case route
               when :normal
                 host.tts_api_request("Hello", **options, instructions: "warm [and] amused")
               when :sentence
                 value = nil
                 host.tts_api_request_async("Hello", **options) { |audio| value = audio }
                 value
               when :cli
                 script.tts_api_request("Hello", **options).transform_keys(&:to_s)
               end
      expect(audio_bytes(result)).to eq(wav)
      expect(client).to have_received(:post) do |url, json:|
        expect(url).to include("/gemini-3.8-flash-lite-tts:generateContent")
        # Flash-Lite speaks even a bracketed style cue as part of the script,
        # so a direction given on the normal route must not reach the text.
        expect(json.dig("contents", 0, "parts", 0, "text")).to eq("Hello")
      end
    end
  end

  it "loads CLI definitions without polluting Object" do
    methods = Object.private_instance_methods(false)
    constants = Object.constants(false)
    script
    expect(Object.private_instance_methods(false)).to eq(methods)
    expect(Object.constants(false)).to eq(constants)
  end

  it "saves the original WAV bytes through the Speech Draft Helper CLI entry point" do
    respond_with(wav, "audio/wav")
    input = "/tmp/gemini-tts-draft.txt"
    allow(File).to receive(:exist?).and_call_original
    allow(File).to receive(:exist?).with(input).and_return(true)
    allow(File).to receive(:read).with(input).and_return("Hello")
    output = StringIO.new("".b)
    expect(File).to receive(:open).with(a_string_ending_with("/gemini-tts-draft.wav"), "wb").and_yield(output)
    previous_argv = ARGV.dup
    begin
      ARGV.replace([input, "--provider=gemini-flash-lite", "--voice=kore"])
      expect { Object.new.instance_eval(File.read(script_path), script_path) }
        .to output(/WAV format/).to_stdout
    ensure
      ARGV.replace(previous_argv)
    end
    expect(output.string).to eq(wav)
  end

  it "resolves the new default and legacy Pro in both request implementations" do
    allow(host).to receive(:resolve_tts_model).and_call_original
    [host, script].each do |receiver|
      expect(receiver.send(:resolve_tts_model, "gemini-flash")).to eq("gemini-3.8-flash-tts")
      expect(receiver.send(:resolve_tts_model, "gemini")).to eq("gemini-3.8-flash-tts")
      expect(receiver.send(:resolve_tts_model, "gemini-pro")).to eq("gemini-2.5-pro-preview-tts")
    end
  end

  it "exposes both new models and all existing models through the Ruby SSOT accessor" do
    models = %w[gemini-3.8-flash-tts gemini-3.8-flash-lite-tts gemini-3.1-flash-tts-preview gemini-2.5-flash-preview-tts gemini-2.5-pro-preview-tts]
    expect(Monadic::Utils::ModelSpec.get_provider_models("gemini", "tts")).to eq(models)
    models.each do |model_name|
      expect(Monadic::Utils::ModelSpec.tts_family(model_name)).to eq("gemini")
      expect(Monadic::Utils::ModelSpec.tts_instructions?(model_name)).to be(true)
      expect(Monadic::Utils::ModelSpec.get_model_property(model_name, "tts_capability")).to be(true)
    end
  end

  describe "style directives" do
    %w[gemini-3.8-flash-tts gemini-3.8-flash-lite-tts gemini-3.1-flash-tts-preview gemini-2.5-flash-preview-tts gemini-2.5-pro-preview-tts].each do |tts_model|
      context tts_model do
        let(:model) { tts_model }

        [nil, "", "warm, amused", "warm [and] amused"].each do |directive|
          it "formats #{directive.inspect} using SSOT without system instructions" do
            respond_with(wav, "audio/wav")
            host.tts_api_request("Hello", provider: "gemini", voice: "kore",
                                 response_format: "wav", speed: 1.0, instructions: directive)
            expected = if directive.nil? || directive.empty? || model == "gemini-3.8-flash-lite-tts"
                         "Hello"
                       elsif model == "gemini-3.8-flash-tts"
                         directive.include?("[") ? "[warm and amused] Hello" : "[warm, amused] Hello"
                       else
                         "Say with this voice and style:\n#{directive}\n\nHello"
                       end
            expect(client).to have_received(:post) do |_, json:|
              expect(json.dig("contents", 0, "parts", 0, "text")).to eq(expected)
              expect(json).not_to have_key("systemInstruction")
              expect(json).not_to have_key("system_instruction")
            end
          end
        end
      end
    end

    it "uses the SSOT flag rather than inferring style syntax from the model name" do
      allow(Monadic::Utils::ModelSpec).to receive(:tts_style_directive).with(model).and_return(nil)
      respond_with(wav, "audio/wav")
      host.tts_api_request("Hello", provider: "gemini", voice: "kore",
                           response_format: "wav", instructions: "warm")
      expect(client).to have_received(:post) do |_, json:|
        expect(json.dig("contents", 0, "parts", 0, "text")).to eq("Say with this voice and style:\nwarm\n\nHello")
      end
    end

    it "omits an empty bracket cue after stripping delimiters and whitespace" do
      respond_with(wav, "audio/wav")
      host.tts_api_request("Hello", provider: "gemini", voice: "kore",
                           response_format: "wav", instructions: " [ ] \n")
      expect(client).to have_received(:post) do |_, json:|
        expect(json.dig("contents", 0, "parts", 0, "text")).to eq("Hello")
      end
    end
  end
end
