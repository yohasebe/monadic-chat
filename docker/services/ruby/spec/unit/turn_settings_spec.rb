# frozen_string_literal: true

require "spec_helper"
require_relative "../../lib/monadic/workspace"

# The settings one message is answered with, read once from the message.
RSpec.describe Monadic::TurnSettings do
  def of(given) = described_class.of(given)

  it "reads each setting the message names" do
    turn = of("model" => "m", "show_thinking" => "true", "websearch" => false, "temperature" => "0.7",
              "max_tokens" => "512", "context_size" => "20", "max_input_tokens" => 8000)
    expect(turn.to_h).to eq(model: "m", show_thinking: true, websearch: false, temperature: 0.7, max_tokens: 512,
                            context_size: 20, max_input_tokens: 8000)
  end

  it "leaves a setting the message does not name unset, apart from one it names as off or zero" do
    expect(of({}).to_h.values).to all(be_nil)
    expect(of(nil).to_h.values).to all(be_nil)
    expect(of("show_thinking" => false).show_thinking).to be(false)
    expect(of("show_thinking" => "false").show_thinking).to be(false)
    expect(of("temperature" => 0).temperature).to eq(0.0)
    expect(of("temperature" => "0").temperature).to eq(0.0)
  end

  it "takes what is not a value of a setting as unset" do
    expect(of("show_thinking" => "yes").show_thinking).to be_nil
    expect(of("temperature" => "warm").temperature).to be_nil
    expect(of("temperature" => "").temperature).to be_nil
    expect(of("temperature" => "1e999").temperature).to be_nil
    expect(of("temperature" => Float::NAN).temperature).to be_nil
    expect(of("websearch" => "on").websearch).to be_nil
    [0, "0", -5, "", "many", "1.5", 1.5, "1e999", "1e3"].each do |value|
      expect(of("max_tokens" => value).max_tokens).to be_nil, value.inspect
      expect(of("context_size" => value).context_size).to be_nil, value.inspect
    end
    expect(of("model" => "").model).to be_nil
  end

  it "does not change with what it was read from" do
    given = { "model" => +"m", "temperature" => "0.5" }
    turn = of(given)
    given["model"] << "-other"
    given["temperature"] = "1.5"
    expect(turn.model).to eq("m")
    expect(turn.temperature).to eq(0.5)
    expect(turn).to be_frozen
    expect { turn.model << "x" }.to raise_error(FrozenError)
  end

  describe ".accepted" do
    let(:kept) { { "model" => "kept", "context_size" => "9", "max_input_tokens" => "4000", "show_thinking" => true,
                   "temperature" => "1.2", "max_tokens" => "900", "websearch" => true } }

    it "takes the chat's model and limits where the message leaves them out, and nothing else of the chat's" do
      turn = described_class.accepted({ "temperature" => "0.3" }, kept)
      expect(turn.to_h).to eq(model: "kept", show_thinking: nil, websearch: nil, temperature: 0.3, max_tokens: nil,
                              context_size: 9, max_input_tokens: 4000)
    end

    it "takes the message's own where it names them" do
      turn = described_class.accepted({ "model" => "m", "context_size" => "3", "max_input_tokens" => "100" }, kept)
      expect(turn.to_h.slice(:model, :context_size, :max_input_tokens)).to eq(model: "m", context_size: 3,
                                                                              max_input_tokens: 100)
    end

    it "is read of a chat that keeps nothing" do
      expect(described_class.accepted({ "model" => "m" }, nil).model).to eq("m")
      expect(described_class.accepted(nil, nil).model).to be_nil
    end
  end

  describe ".current" do
    it "is the settings of the request being answered, whatever the given parameters say" do
      settings = of("model" => "of-the-message", "show_thinking" => false)
      context = Monadic::Workspace::RequestContext.new(chat_id: "c", settings: settings)
      Monadic::Workspace::RequestContext.with(context) do
        expect(described_class.current("model" => "kept", "show_thinking" => true)).to equal(settings)
      end
    end

    it "is read from the given parameters where no message was accepted for the request" do
      expect(described_class.current("model" => "m").model).to eq("m")
      context = Monadic::Workspace::RequestContext.new(chat_id: "c")
      Monadic::Workspace::RequestContext.with(context) do
        expect(described_class.current("model" => "m").model).to eq("m")
      end
    end
  end
end
