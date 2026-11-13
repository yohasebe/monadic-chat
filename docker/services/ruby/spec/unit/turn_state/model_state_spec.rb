# frozen_string_literal: true

require_relative "../../spec_helper"
require_relative "../../../lib/monadic/turn_state/model_state"
require_relative "../../../lib/monadic/utils/system_prompt_injector"

# An app's state as the model is given it with each request.
RSpec.describe Monadic::TurnState::ModelState do
  let(:chat) { Monadic::Workspace::Ids.generate(:chat) }
  let(:session) do
    { Monadic::Workspace::Chats::SESSION_KEY => chat, messages: [], parameters: { "app_name" => "Stateful" } }
  end
  let(:state) { { target_lang: "English", last_message: "Hi" } }
  let(:load_tool) { "load_context" }
  let(:app) do
    data = -> { state }
    tool = -> { load_tool }
    Class.new do
      define_method(:state_for_model) { |_session| { data: data.call, load_tool: tool.call } }
      private :state_for_model
    end.new
  end
  let(:words) { Monadic::Utils::Privacy::Words }

  before { stub_const("APPS", { "Stateful" => app, "Plain" => Object.new }) }
  after { words::LOCK.synchronize { words::TABLES.clear } }

  def prompt
    described_class.prompt(session)
  end

  it "gives the state as data between two lines, said to be current and not instructions" do
    expect(prompt).to include("not instructions", "do not load it", described_class::OPEN, described_class::CLOSE)
    expect(JSON.parse(prompt[/#{described_class::OPEN}\n(.*)\n#{described_class::CLOSE}/m, 1]))
      .to eq("target_lang" => "English", "last_message" => "Hi")
  end

  context "with nothing saved" do
    let(:state) { { target_lang: nil, last_message: nil, topics: [] } }

    it "says there is none, and not to load it" do
      expect(prompt).to eq(described_class::NONE)
    end
  end

  context "with more than fits" do
    let(:state) { { findings: ["x" * (described_class::LIMIT + 1)] } }

    it "does not give a part of it, and names the load tool" do
      expect(prompt).to eq(format(described_class::NOT_GIVEN_LOAD, tool: "load_context"))
    end

    context "in an app without a load tool" do
      let(:load_tool) { nil }

      it "names no tool" do
        expect(prompt).to eq(described_class::NOT_GIVEN)
      end
    end
  end

  it "says the state is not given, rather than that there is none, when it cannot be made" do
    allow(app).to receive(:state_for_model).and_raise(StandardError, "boom")

    expect(prompt).to eq(described_class::NOT_GIVEN)
  end

  context "in an app that does not offer its load tool to the model" do
    before do
      allow(app).to receive(:settings).and_return({ tools: [{ "type" => "function", "function" => { "name" => "other" } }] })
    end

    it "gives nothing" do
      expect(prompt).to be_nil
    end

    it "gives the state once the tool is offered, however the provider lists it" do
      allow(app).to receive(:settings).and_return({ tools: { "function_declarations" => [{ name: "load_context" }] } })

      expect(prompt).to include(described_class::OPEN)
    end
  end

  it "gives nothing for an app that does not say what the model is given" do
    session[:parameters]["app_name"] = "Plain"

    expect(prompt).to be_nil
    expect(described_class.declaring_app(session)).to be_nil
  end

  context "in a chat that hides words" do
    let(:state) { { target_lang: "English", last_message: "Tanaka called", people: ["Tanaka"] } }

    it "gives the state with the words hidden, as a tool's result is" do
      table = words.start!(session)
      table.confirm_all!([%w[Tanaka PERSON]])

      expect(prompt).not_to include("Tanaka")
      expect(table.snapshot.restore(prompt)).to include("Tanaka called")
    end

    it "does not give a state one of whose keys holds a hidden word" do
      state[:Tanaka] = "x"
      words.start!(session).confirm_all!([%w[Tanaka PERSON]])

      expect(prompt).to eq(format(described_class::NOT_GIVEN_LOAD, tool: "load_context"))
    end
  end

  describe "the prompt rule" do
    def rule_names
      Monadic::Utils::SystemPromptInjector.build_injections(session: session).map { |i| i[:name] }
    end

    it "is added last for an app that says what the model is given, and not otherwise" do
      expect(rule_names.last).to eq(:app_state)

      session[:parameters]["app_name"] = "Plain"
      expect(rule_names).not_to include(:app_state)
    end
  end
end
