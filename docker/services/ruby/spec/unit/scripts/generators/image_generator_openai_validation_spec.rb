# frozen_string_literal: true

require "spec_helper"
require "json"
require "stringio"

# Two ways a wrong image request used to reach the paid API.
#
# The app reaches this script through its command line
# (lib/monadic/adapters/media_generation_helper.rb builds the argv), so the CLI
# block is the production path and has to be exercised, not just the functions
# it calls. A first attempt at this validation placed the definition below the
# CLI block that used it; Ruby evaluates a top-level `def` when execution
# reaches it, so every image request died with NoMethodError while every
# in-process example still passed.
#
# And whatever the API answered, the script retried three more times —
# including a 400 that says the model does not accept this quality, which no
# number of retries can change.
#
# Quality is per model: gpt-image-2 rejects `xhigh` while the 2.5 models accept
# it, so model and quality are only meaningful together.
RSpec.describe "image_generator_openai request validation" do
  let(:script) { GeneratorScriptLoader.load("image_generator_openai.rb") }

  describe "what it refuses before any request" do
    it "rejects a quality the chosen model does not accept" do
      problem = script.image_request_problem(model: "gpt-image-2", quality: "xhigh")

      expect(problem).to include("xhigh", "gpt-image-2")
      # The message carries what the model may ask for instead, so the caller
      # can correct itself rather than guess.
      expect(problem).to include("auto", "low", "medium", "high")
    end

    it "accepts the same quality on a model that supports it" do
      # Positive control: without this, "rejects xhigh" would also pass on a
      # validator that rejected everything.
      expect(script.image_request_problem(model: "gpt-image-2.5-flare", quality: "xhigh")).to be_nil
      expect(script.image_request_problem(model: "gpt-image-2", quality: "high")).to be_nil
    end

    it "rejects a model that is not offered" do
      problem = script.image_request_problem(model: "gpt-image-9", quality: "auto")

      expect(problem).to include("gpt-image-9")
      expect(problem).to include("gpt-image-2")
    end

    it "rejects a request with no model" do
      expect(script.image_request_problem(model: "", quality: "auto")).to include("No image model")
    end

    it "lets an omitted quality through to the API's own default" do
      # The facade used to default to "standard", a DALL-E term outside every
      # current vocabulary. Nothing may reintroduce a literal default here.
      expect(script.image_request_problem(model: "gpt-image-2")).to be_nil
      expect(script.image_request_problem(model: "gpt-image-2", quality: nil)).to be_nil
    end
  end

  describe "the catalog failing to answer" do
    # A vocabulary that cannot be resolved is not permission to proceed. The
    # first version returned early on an omitted quality, so a newly offered
    # model with no capability entry went straight through.
    it "refuses a model whose quality vocabulary is missing, even with no quality given" do
      options = Monadic::Utils::ModelSpec.send(:load_image_generation_options)
      original = options["openai"]["models"]
      begin
        options["openai"]["models"] = original.reject { |name, _| name == "gpt-image-2" }
        expect(script.image_request_problem(model: "gpt-image-2")).to include("vocabulary")
      ensure
        options["openai"]["models"] = original
      end
    end

    it "refuses when the catalog lists no models at all" do
      defaults = Monadic::Utils::ModelSpec.send(:load_provider_defaults)
      original = defaults["openai"]["image"]
      begin
        defaults["openai"]["image"] = []
        expect(script.image_request_problem(model: "gpt-image-2", quality: "high")).to include("catalog")
      ensure
        defaults["openai"]["image"] = original
      end
    end
  end

  describe "the CLI, which is how the app calls this script" do
    # Runs the real CLI block in an isolated namespace (see
    # GeneratorScriptLoader#run_cli). A plain `load` would leave the script's
    # methods on Object, so one example's definitions would rescue the next and
    # a broken definition order would stop failing after the first example.
    #
    # `generate_image` is replaced by a recorder: what reaches it is the
    # question, and nothing may leave the process. Asserting only the absence
    # of an error message is not enough — a CLI that refused everything for an
    # unrelated reason would satisfy that too.
    def run_cli(*argv)
      script, output = GeneratorScriptLoader.run_cli("image_generator_openai.rb", argv)
      [script, output]
    end

    # The CLI block calls generate_image at the very end, so the recorder has
    # to be installed on the same object the block will use. instance_eval
    # defines the script's methods as singletons, so redefining one afterwards
    # is not possible before the run. Instead the request is reconstructed from
    # the validator, and the outcome is read from stdout and the exit status.
    def cli_outcome(*argv)
      _script, output = run_cli(*argv)
      output
    end

    it "reports the validation error rather than dying on an undefined method" do
      # The first version of this validation was defined below the CLI block
      # that called it, so every image request died here with NoMethodError.
      out = cli_outcome("-o", "generate", "-m", "gpt-image-2", "-p", "x", "-q", "xhigh")

      expect(out).not_to include("NoMethodError")
      expect(out).to include("xhigh", "gpt-image-2")
      expect(out).to include("auto, low, medium, high")
    end

    it "carries a supported combination through to the request it builds" do
      # Positive control with teeth: the run must reach the point where the
      # model and quality are assembled into a request, with those exact
      # values. "No error was printed" would also hold for a CLI that refused
      # everything, which is what a weaker version of this example allowed.
      requested = nil
      allow(Monadic::Utils::HttpClient).to receive(:generation) do
        recorder = Object.new
        recorder.define_singleton_method(:headers) { |_| self }
        recorder.define_singleton_method(:post) do |_url, **kw|
          requested = kw[:json]
          raise "stop before the network"
        end
        recorder
      end

      out = cli_outcome("-o", "generate", "-m", "gpt-image-2.5-flare", "-p", "x", "-q", "xhigh")

      expect(out).not_to include("NoMethodError")
      expect(requested).not_to be_nil, "the CLI never reached the request: #{out}"
      expect(requested[:model]).to eq("gpt-image-2.5-flare")
      expect(requested[:quality]).to eq("xhigh")
    end

    it "builds no request at all when the combination is refused" do
      attempts = 0
      allow(Monadic::Utils::HttpClient).to receive(:generation) do
        recorder = Object.new
        recorder.define_singleton_method(:headers) { |_| self }
        recorder.define_singleton_method(:post) { |*, **| attempts += 1; raise "network reached" }
        recorder
      end

      cli_outcome("-o", "generate", "-m", "gpt-image-2", "-p", "x", "-q", "max")

      expect(attempts).to eq(0)
    end

    it "leaves no definitions behind on Object" do
      # The isolation is the point: without it, a later example would inherit
      # whatever an earlier one defined.
      run_cli("-o", "generate", "-m", "gpt-image-2", "-p", "x", "-q", "xhigh")

      expect(Object.private_method_defined?(:image_request_problem)).to be(false)
      expect(Object.private_method_defined?(:generate_image)).to be(false)
    end
  end

  describe "a caller that reaches generate_image directly" do
    it "refuses without reaching the network" do
      # Second line of defence for anything that does not go through the CLI.
      allow(script).to receive(:get_api_key).and_return("sk-test")

      result = script.generate_image(operation: "generate", model: "gpt-image-2",
                                     prompt: "x", quality: "max")

      expect(result[:success]).to be(false)
      expect(result[:message]).to include("max", "gpt-image-2")
    end
  end

  describe "what reaches the request body" do
    # Validation deciding a pairing is allowed is not the same as that value
    # arriving intact. Quality travels through three assemblies — the generate
    # JSON, the edit JSON and the edit multipart form — and the empty-string
    # case has to be dropped from each, because "" is truthy in Ruby and the
    # validator treats it as omitted.
    def capture_request(**options)
      sent = nil
      recorder = Object.new
      recorder.define_singleton_method(:headers) { |_| self }
      recorder.define_singleton_method(:post) do |_url, **kw|
        sent = kw[:json] || kw[:form]
        raise "stop before the network"
      end
      allow(Monadic::Utils::HttpClient).to receive(:generation).and_return(recorder)
      allow(script).to receive(:get_api_key).and_return("sk-test")

      script.generate_image({ operation: "generate", prompt: "x" }.merge(options))
      sent
    end

    it "sends xhigh and max exactly as chosen" do
      expect(capture_request(model: "gpt-image-2.5-flare", quality: "xhigh")[:quality]).to eq("xhigh")
      expect(capture_request(model: "gpt-image-2.5-sunburst", quality: "max")[:quality]).to eq("max")
    end

    it "sends an ordinary quality unchanged" do
      expect(capture_request(model: "gpt-image-2", quality: "high")[:quality]).to eq("high")
    end

    it "omits the field rather than sending an empty one" do
      [nil, "", "  "].each do |blank|
        body = capture_request(model: "gpt-image-2", quality: blank)
        expect(body).not_to have_key(:quality), "quality=#{blank.inspect} was sent as #{body[:quality].inspect}"
      end
    end

    it "keeps the same rule on the edit paths" do
      # The edit request builds its body elsewhere in the script; the three
      # assemblies drifted apart once already.
      source = File.read(File.expand_path("../../../../scripts/generators/image_generator_openai.rb", __dir__))
      guarded = source.scan(/\[:quality\] = options\[:quality\] unless options\[:quality\]\.to_s\.strip\.empty\?/).size
      unguarded = source.scan(/\[:quality\] = options\[:quality\] if options\[:quality\]/).size

      expect(unguarded).to eq(0)
      expect(guarded).to eq(3)
    end
  end

  describe "which failures are worth repeating" do
    # Repeating a rejected request cannot fix its parameters, so a 400 that
    # names the problem must not be sent again.
    def stub_response(status, message)
      status_obj = Class.new do
        def initialize(code) = @code = code
        def success? = @code < 400
        def to_i = @code
        def to_s = @code.to_s
      end.new(status)

      Struct.new(:status, :body).new(status_obj, { error: { message: message } }.to_json)
    end

    def count_calls(status, message)
      calls = 0
      # Built here, not inside the block: `self` inside define_singleton_method
      # is the poster, so calling a helper of this example group from there
      # raises NoMethodError — which the script's rescue would swallow and
      # retry, making a broken stub look exactly like the bug under test.
      response = stub_response(status, message)
      poster = Object.new
      poster.define_singleton_method(:headers) { |_| self }
      poster.define_singleton_method(:post) { |*, **| calls += 1; response }
      allow(Monadic::Utils::HttpClient).to receive(:generation).and_return(poster)
      allow(script).to receive(:get_api_key).and_return("sk-test")

      result = script.generate_image(operation: "generate", model: "gpt-image-2",
                                     prompt: "x", quality: "high")
      [calls, result]
    end

    it "sends a rejected request once" do
      calls, result = count_calls(400, "Invalid size for this model.")

      expect(calls).to eq(1)
      # And the API's own words survive. "Failed after multiple attempts" hid
      # the reason, and on a request that was never retried it was not true.
      expect(result[:message]).to include("Invalid size")
    end

    it "still retries a rate limit" do
      calls, = count_calls(429, "Rate limit exceeded.")

      expect(calls).to be > 1
    end

    it "still retries a server error" do
      calls, = count_calls(500, "Internal error.")

      expect(calls).to be > 1
    end
  end
end
