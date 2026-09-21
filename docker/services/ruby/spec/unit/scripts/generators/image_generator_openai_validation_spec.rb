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
    # Run the CLI block in this process. Spawning the script is forbidden here
    # and for good reason — a generator spec that shelled out once generated a
    # real image and billed for it (see no_network_spec.rb) — so $PROGRAM_NAME
    # is pointed at the script instead, which makes its `__FILE__` guard true
    # without a subprocess. HTTP is not reachable from this path: validation
    # either stops first, or the request fails on the absent key.
    SCRIPT_PATH = File.expand_path("../../../../scripts/generators/image_generator_openai.rb", __dir__)

    def run_cli(*argv)
      raise "script not found at #{SCRIPT_PATH}" unless File.exist?(SCRIPT_PATH)

      previous_program, previous_argv = $PROGRAM_NAME, ARGV.dup
      output = StringIO.new
      begin
        $PROGRAM_NAME = SCRIPT_PATH
        ARGV.replace(argv)
        $stdout = output
        begin
          load SCRIPT_PATH
        rescue SystemExit
          # `exit 1` on a rejected request is the outcome under test.
        end
      ensure
        $stdout = STDOUT
        $PROGRAM_NAME = previous_program
        ARGV.replace(previous_argv)
      end
      output.string
    end

    before do
      # Any request that did get past validation must not leave this process.
      allow(Monadic::Utils::HttpClient).to receive(:generation) { raise "network reached" }
    end

    it "reports the validation error rather than dying on an undefined method" do
      # The first version of this validation was defined below the CLI block
      # that called it, so every request died here with NoMethodError.
      out = run_cli("-o", "generate", "-m", "gpt-image-2", "-p", "x", "-q", "xhigh")

      expect(out).not_to include("NoMethodError")
      expect(out).to include("xhigh", "gpt-image-2")
    end

    it "lets a supported combination past validation" do
      # Positive control: without it, "no NoMethodError" would also hold for a
      # CLI that rejected everything.
      out = run_cli("-o", "generate", "-m", "gpt-image-2.5-flare", "-p", "x", "-q", "xhigh")

      expect(out).not_to include("NoMethodError")
      expect(out).not_to include("is not supported by")
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

  describe "which failures are worth repeating" do
    # Each attempt is another billable call, so a 400 that names the problem
    # must not be sent again.
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
