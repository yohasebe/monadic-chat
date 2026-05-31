# frozen_string_literal: true

require_relative "../../spec_helper"
require "monadic/substitution/context"

RSpec.describe Monadic::Substitution::Context do
  let(:session) { { messages: [] } }
  let(:app) { double("App") }

  describe "#initialize" do
    it "stores session and app" do
      ctx = described_class.new(session: session, app: app)
      expect(ctx.session).to be(session)
      expect(ctx.app).to be(app)
    end

    it "accepts nil app" do
      ctx = described_class.new(session: session)
      expect(ctx.app).to be_nil
    end
  end

  describe "#app_name" do
    it "returns the unqualified class name of the active app" do
      stub_const("MonadicTestApp", Class.new)
      ctx = described_class.new(session: session, app: MonadicTestApp.new)
      expect(ctx.app_name).to eq("MonadicTestApp")
    end

    it "returns nil when no app is set" do
      ctx = described_class.new(session: session)
      expect(ctx.app_name).to be_nil
    end
  end

  describe "#messages" do
    it "returns the messages array from the session" do
      session[:messages] = [{ "role" => "user", "text" => "hi" }]
      ctx = described_class.new(session: session)
      expect(ctx.messages).to eq([{ "role" => "user", "text" => "hi" }])
    end

    it "returns an empty array when session has no messages key" do
      ctx = described_class.new(session: {})
      expect(ctx.messages).to eq([])
    end
  end

  describe "#turn_count" do
    it "counts user messages only" do
      session[:messages] = [
        { "role" => "user", "text" => "q1" },
        { "role" => "assistant", "text" => "a1" },
        { "role" => "user", "text" => "q2" },
        { "role" => "system", "text" => "boot" }
      ]
      ctx = described_class.new(session: session)
      expect(ctx.turn_count).to eq(2)
    end

    it "returns 0 for an empty session" do
      ctx = described_class.new(session: {})
      expect(ctx.turn_count).to eq(0)
    end
  end
end
