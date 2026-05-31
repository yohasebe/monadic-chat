# frozen_string_literal: true

require_relative "../../spec_helper"
require "monadic/substitution/pipeline"

RSpec.describe Monadic::Substitution::Pipeline do
  let(:session) { { messages: [] } }
  let(:pipeline) { described_class.new(session: session) }

  # ---- Test doubles ---------------------------------------------------------

  # Recording provider that captures every hook call and returns predictable
  # transforms (suffixed strings, marked hashes) so order can be asserted.
  let(:recording_provider_class) do
    Class.new(Monadic::Substitution::Provider) do
      attr_reader :calls
      def initialize(tag:, failure_mode: :open)
        super()
        @tag = tag
        @failure_mode = failure_mode
        @calls = []
      end
      def name; "Rec#{@tag}"; end
      def failure_mode; @failure_mode; end
      def on_input(message, _ctx); @calls << :input; "#{message}<#{@tag}>"; end
      def on_tool_invoke(name, args, _ctx); @calls << [:tool, name]; args.merge(@tag => true); end
      def on_output_render(text, _ctx); @calls << :output; "#{text}<#{@tag}>"; end
      def system_prompt_addendum(_ctx); "addendum-#{@tag}"; end
      def owns_token?(name); name == @tag.to_s.upcase; end
      def resolve(name, _ctx); "resolved-#{name}-by-#{@tag}"; end
    end
  end

  let(:raising_provider_class) do
    Class.new(Monadic::Substitution::Provider) do
      def initialize(failure_mode: :open)
        super()
        @failure_mode = failure_mode
      end
      def failure_mode; @failure_mode; end
      def on_input(_message, _ctx); raise "boom"; end
      def on_tool_invoke(_name, _args, _ctx); raise "boom"; end
      def on_output_render(_text, _ctx); raise "boom"; end
      def system_prompt_addendum(_ctx); raise "boom"; end
      def owns_token?(name); name == "BOOM"; end
      def resolve(_name, _ctx); raise "boom"; end
    end
  end

  # ---- Registration ---------------------------------------------------------

  describe "#register" do
    it "accepts a Provider instance" do
      provider = recording_provider_class.new(tag: :a)
      expect { pipeline.register(provider) }.not_to raise_error
      expect(pipeline.providers).to include(provider)
    end

    it "rejects non-Provider objects" do
      expect { pipeline.register("not a provider") }
        .to raise_error(ArgumentError, /Expected Substitution::Provider/)
    end

    it "rejects duplicate registration of the same instance" do
      provider = recording_provider_class.new(tag: :a)
      pipeline.register(provider)
      expect { pipeline.register(provider) }
        .to raise_error(ArgumentError, /already registered/)
    end

    it "returns self for chaining" do
      provider = recording_provider_class.new(tag: :a)
      expect(pipeline.register(provider)).to be(pipeline)
    end
  end

  describe "#providers" do
    it "returns providers in registration order" do
      a = recording_provider_class.new(tag: :a)
      b = recording_provider_class.new(tag: :b)
      pipeline.register(a).register(b)
      expect(pipeline.providers).to eq([a, b])
    end

    it "returns a frozen snapshot" do
      pipeline.register(recording_provider_class.new(tag: :a))
      expect(pipeline.providers).to be_frozen
    end

    it "is empty by default" do
      expect(pipeline.providers).to eq([])
    end
  end

  # ---- Input lifecycle ------------------------------------------------------

  describe "#process_input" do
    it "applies providers in registration order" do
      pipeline.register(recording_provider_class.new(tag: :a))
      pipeline.register(recording_provider_class.new(tag: :b))
      expect(pipeline.process_input("hi")).to eq("hi<a><b>")
    end

    it "returns the message unchanged when no providers are registered" do
      expect(pipeline.process_input("hi")).to eq("hi")
    end

    it "logs and continues when an :open provider raises" do
      raising = raising_provider_class.new(failure_mode: :open)
      after = recording_provider_class.new(tag: :z)
      pipeline.register(raising).register(after)
      expect(pipeline.process_input("hi")).to eq("hi<z>")
    end

    it "propagates when a :closed provider raises" do
      raising = raising_provider_class.new(failure_mode: :closed)
      pipeline.register(raising)
      expect { pipeline.process_input("hi") }.to raise_error(RuntimeError, "boom")
    end
  end

  # ---- Tool invocation lifecycle -------------------------------------------

  describe "#process_tool_invoke" do
    it "applies providers in registration order" do
      pipeline.register(recording_provider_class.new(tag: :a))
      pipeline.register(recording_provider_class.new(tag: :b))
      result = pipeline.process_tool_invoke("ls", {})
      expect(result).to eq({ a: true, b: true })
    end

    it "passes the tool name to each provider" do
      provider = recording_provider_class.new(tag: :a)
      pipeline.register(provider)
      pipeline.process_tool_invoke("read_file", {})
      expect(provider.calls).to include([:tool, "read_file"])
    end

    it "returns args unchanged when no providers are registered" do
      args = { path: "/x" }
      expect(pipeline.process_tool_invoke("any", args)).to be(args)
    end
  end

  # ---- Output rendering lifecycle ------------------------------------------

  describe "#process_output" do
    it "applies providers in registration order" do
      pipeline.register(recording_provider_class.new(tag: :a))
      pipeline.register(recording_provider_class.new(tag: :b))
      expect(pipeline.process_output("hi")).to eq("hi<a><b>")
    end

    it "returns text unchanged when no providers are registered" do
      expect(pipeline.process_output("hi")).to eq("hi")
    end
  end

  # ---- System prompt addendum collection -----------------------------------

  describe "#system_prompt_addenda" do
    it "collects addenda in registration order" do
      pipeline.register(recording_provider_class.new(tag: :first))
      pipeline.register(recording_provider_class.new(tag: :second))
      expect(pipeline.system_prompt_addenda).to eq(["addendum-first", "addendum-second"])
    end

    it "skips providers that return nil" do
      nil_provider = Class.new(Monadic::Substitution::Provider) do
        def system_prompt_addendum(_ctx); nil; end
      end.new
      pipeline.register(nil_provider)
      pipeline.register(recording_provider_class.new(tag: :a))
      expect(pipeline.system_prompt_addenda).to eq(["addendum-a"])
    end

    it "skips providers that return an empty string" do
      empty_provider = Class.new(Monadic::Substitution::Provider) do
        def system_prompt_addendum(_ctx); ""; end
      end.new
      pipeline.register(empty_provider)
      pipeline.register(recording_provider_class.new(tag: :a))
      expect(pipeline.system_prompt_addenda).to eq(["addendum-a"])
    end

    it "returns [] for an empty pipeline" do
      expect(pipeline.system_prompt_addenda).to eq([])
    end

    it "swallows :open provider errors and continues with subsequent providers" do
      pipeline.register(raising_provider_class.new(failure_mode: :open))
      pipeline.register(recording_provider_class.new(tag: :a))
      expect(pipeline.system_prompt_addenda).to eq(["addendum-a"])
    end
  end

  # ---- Token resolution chain ----------------------------------------------

  describe "#resolve_token" do
    it "returns the first owner's resolved value" do
      pipeline.register(recording_provider_class.new(tag: :a))
      pipeline.register(recording_provider_class.new(tag: :b))
      expect(pipeline.resolve_token("A")).to eq("resolved-A-by-a")
    end

    it "delegates to the correct provider when names differ" do
      pipeline.register(recording_provider_class.new(tag: :a))
      pipeline.register(recording_provider_class.new(tag: :b))
      expect(pipeline.resolve_token("B")).to eq("resolved-B-by-b")
    end

    it "returns nil when no provider owns the token" do
      pipeline.register(recording_provider_class.new(tag: :a))
      expect(pipeline.resolve_token("UNKNOWN")).to be_nil
    end

    it "returns nil for an empty pipeline" do
      expect(pipeline.resolve_token("ANYTHING")).to be_nil
    end
  end

  # ---- Context handling ----------------------------------------------------

  describe "#context" do
    it "is memoized" do
      first = pipeline.context
      second = pipeline.context
      expect(first).to equal(second)
    end

    it "carries session and app" do
      stub_const("MonadicTestApp", Class.new)
      app = MonadicTestApp.new
      pipeline = described_class.new(session: session, app: app)
      expect(pipeline.context.session).to be(session)
      expect(pipeline.context.app).to be(app)
    end
  end
end
