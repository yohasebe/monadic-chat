# frozen_string_literal: true

require "spec_helper"
require_relative "../../../lib/monadic/shared_tools/registry"
require_relative "../../../lib/monadic/adapters/read_write_helper"
require_relative "../../../lib/monadic/utils/system_prompt_injector"

RSpec.describe "Capability notes in the system prompt" do
  let(:flag) { Monadic::Utils::CapabilityNotes::FLAG }
  let(:settings) do
    { "provider" => "openai",
      "tools" => [{ "type" => "function", "function" => { "name" => "fetch_text_from_pdf" } }] }
  end
  let(:session) { { parameters: { "app_name" => "NotesApp", "math" => true } } }
  let(:base) { "You help with speeches." }

  before do
    stub_const("APPS", { "NotesApp" => double("app", settings: settings) })
    stub_const("CONFIG", {})
    allow(Monadic::Utils::ContainerProbe).to receive(:check).and_return({ state: :stopped })
    allow(ENV).to receive(:[]).and_call_original
  end

  def augmented
    Monadic::Utils::SystemPromptInjector.augment(base_prompt: base, session: session, separator: "\n\n")
  end

  it "adds nothing, and asks no container, when the flag does not name the app" do
    allow(ENV).to receive(:[]).with(flag).and_return(nil)
    expect(augmented).not_to include("What your tools can do now")
    expect(Monadic::Utils::ContainerProbe).not_to have_received(:check)
  end

  it "puts the note last, after every other part of the prompt" do
    allow(ENV).to receive(:[]).with(flag).and_return("NotesApp")
    text = augmented
    expect(text).to start_with(base)
    expect(text.scan("What your tools can do now").size).to eq(1)
    expect(text).to end_with("ask the user to paste the text instead.")
  end

  it "leaves the prompt before the note as it is without the flag" do
    allow(ENV).to receive(:[]).with(flag).and_return(nil)
    without = augmented
    allow(ENV).to receive(:[]).with(flag).and_return("NotesApp")
    expect(augmented).to start_with(without)
  end
end
