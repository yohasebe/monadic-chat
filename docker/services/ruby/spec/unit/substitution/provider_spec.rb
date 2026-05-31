# frozen_string_literal: true

require_relative "../../spec_helper"
require "monadic/substitution/provider"
require "monadic/substitution/context"

RSpec.describe Monadic::Substitution::Provider do
  let(:provider) { described_class.new }
  let(:session) { { messages: [] } }
  let(:context) { Monadic::Substitution::Context.new(session: session) }

  describe "default lifecycle hooks (no-op identity)" do
    it "#on_input returns the message unchanged" do
      expect(provider.on_input("hello", context)).to eq("hello")
    end

    it "#on_tool_invoke returns args unchanged" do
      args = { path: "/foo", recursive: true }
      expect(provider.on_tool_invoke("list", args, context)).to be(args)
    end

    it "#on_output_render returns text unchanged" do
      expect(provider.on_output_render("text", context)).to eq("text")
    end

    it "#system_prompt_addendum returns nil" do
      expect(provider.system_prompt_addendum(context)).to be_nil
    end
  end

  describe "default token resolution" do
    it "#owns_token? returns false for any name" do
      expect(provider.owns_token?("SHARED")).to be(false)
      expect(provider.owns_token?("PERSON_1")).to be(false)
    end

    it "#resolve returns nil for any name" do
      expect(provider.resolve("ANY_TOKEN", context)).to be_nil
    end
  end

  describe "#name" do
    it "returns the unqualified class name" do
      stub_const("Monadic::Substitution::FooProvider", Class.new(described_class))
      expect(Monadic::Substitution::FooProvider.new.name).to eq("FooProvider")
    end

    it "memoizes the result" do
      first = provider.name
      second = provider.name
      expect(first).to equal(second)
    end
  end

  describe "#failure_mode" do
    it "defaults to :open" do
      expect(provider.failure_mode).to eq(:open)
    end
  end

  describe "#state" do
    it "creates a per-provider state slot on the session" do
      slot = provider.state(context)
      expect(slot).to be_a(Hash)
      slot[:registry] = { foo: 1 }
      expect(provider.state(context)[:registry]).to eq({ foo: 1 })
    end

    it "uses provider name as the namespace key" do
      stub_const("Monadic::Substitution::AnotherProvider", Class.new(described_class))
      another = Monadic::Substitution::AnotherProvider.new

      provider.state(context)[:flag] = "one"
      another.state(context)[:flag] = "two"

      expect(provider.state(context)[:flag]).to eq("one")
      expect(another.state(context)[:flag]).to eq("two")
    end

    it "does not collide with unrelated session keys" do
      session[:other_data] = "untouched"
      provider.state(context)[:x] = 1
      expect(session[:other_data]).to eq("untouched")
    end
  end
end
