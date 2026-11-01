# frozen_string_literal: true

require "spec_helper"
require_relative "../../../lib/monadic/shared_tools/registry"
require_relative "../../../lib/monadic/adapters/read_write_helper"
require_relative "../../../lib/monadic/utils/capability_notes"

RSpec.describe Monadic::Utils::CapabilityNotes do
  def tool(name)
    { "type" => "function", "function" => { "name" => name, "description" => "" } }
  end

  let(:settings) do
    {
      "provider" => "openai",
      "tools" => %w[fetch_text_from_file fetch_text_from_pdf fetch_text_from_office text_to_speech request_tool
                    analyze_image].map { |n| tool(n) },
      "progressive_tools" => {
        "always_visible" => %w[fetch_text_from_file fetch_text_from_pdf fetch_text_from_office text_to_speech request_tool],
        "conditional" => [{ "name" => "analyze_image", "unlock_conditions" => [{ "tool_request" => "image_analysis" }] }],
        "all_tool_names" => %w[fetch_text_from_file fetch_text_from_pdf fetch_text_from_office text_to_speech
                               request_tool analyze_image]
      },
      imported_tool_groups: [
        { name: :file_operations, visibility: "always" },
        { name: :image_analysis, visibility: "conditional" }
      ]
    }
  end
  let(:session) { { parameters: { "app_name" => "NotesApp" } } }
  let(:config) { { "OPENAI_API_KEY" => "k" } }
  let(:ready) { ->(_service) { { state: :ready } } }

  let(:speech_keys) { { "OPENAI_API_KEY" => "k" } }

  def note(probe: ready, config: self.config, session: self.session, speech_keys: self.speech_keys)
    described_class.build(settings: settings, session: session, app_name: "NotesApp", config: config, probe: probe,
                          speech_keys: speech_keys)
  end

  describe ".enabled_for?" do
    it "is on only for the apps the flag names" do
      env = { described_class::FLAG => "OtherApp, NotesApp" }
      expect(described_class.enabled_for?("NotesApp", env)).to be(true)
      expect(described_class.enabled_for?("ThirdApp", env)).to be(false)
    end

    it "is off without the flag or without an app" do
      expect(described_class.enabled_for?("NotesApp", {})).to be(false)
      expect(described_class.enabled_for?("", { described_class::FLAG => "" })).to be(false)
    end
  end

  describe ".build" do
    it "tells the model to unlock a conditional analysis group, and that its provider and key are set" do
      expect(note).to include('Image analysis: call request_tool("image_analysis") first to get analyze_image; ready: the provider supports it')
    end

    it "says the group is offered once one of its tools is unlocked" do
      unlocked = session.merge(progressive_tools: { "NotesApp" => { unlocked: ["analyze_image"] } })
      expect(note(session: unlocked)).to include("Image analysis: offered as analyze_image; ready")
    end

    it "leaves out a group that is neither sent nor unlockable" do
      settings["progressive_tools"]["conditional"] = []
      expect(note).not_to include("Image analysis")
    end

    it "reports an analysis the provider cannot do, from the provider check" do
      no_key = note(config: {})
      expect(no_key).to include("Image analysis:")
      expect(no_key).to include("not available: Image analysis with 'openai' needs OPENAI_API_KEY")
    end

    it "names the Python readers only, and says when their container is stopped" do
      text = note(probe: ->(_s) { { state: :stopped } })
      expect(text).to include("Reading documents with fetch_text_from_office, fetch_text_from_pdf: not ready: the Python container is not running")
      expect(note).to include("ready: the Python container is running")
      expect(text).not_to include("fetch_text_from_file:")
    end

    it "keeps an unknown container apart from a stopped one" do
      text = note(probe: ->(_s) { { state: :unknown, reason: "docker did not answer" } })
      expect(text).to include("could not be checked (docker did not answer)")
      expect(text).not_to include("not running")
    end

    it "marks each speech provider by the key the speech command can read, not the server's" do
      text = note(config: { "OPENAI_API_KEY" => "k", "GEMINI_API_KEY" => "g", "ELEVENLABS_API_KEY" => "e" },
                  speech_keys: { "OPENAI_API_KEY" => "k", "GEMINI_API_KEY" => " " })
      expect(text).to include("openai ready; elevenlabs not available (ELEVENLABS_API_KEY is not set); gemini not available (GEMINI_API_KEY is not set)")
    end

    it "never puts a key's value in the note" do
      text = note(config: { "OPENAI_API_KEY" => "secret-value-123" }, speech_keys: { "OPENAI_API_KEY" => "secret-value-123" })
      expect(text).not_to include("secret-value-123")
    end

    it "is the same text while nothing it reports changes" do
      expect(note).to eq(note)
    end

    it "asks the container once per probe call and not for apps without Python readers" do
      asked = []
      probe = ->(service) { asked << service; { state: :ready } }
      note(probe: probe)
      expect(asked).to eq([:python])

      settings["tools"] = [tool("text_to_speech")]
      asked.clear
      note(probe: probe)
      expect(asked).to be_empty
    end

    it "is nil when the app has none of the tools it reports on" do
      bare = { "provider" => "openai", "tools" => [tool("other")] }
      expect(described_class.build(settings: bare, session: session, app_name: "NotesApp", config: config, probe: ready,
                                   speech_keys: speech_keys)).to be_nil
    end
  end

  describe ".for_session" do
    let(:app) { double("app", settings: settings) }

    before { stub_const("APPS", { "NotesApp" => app }) }

    it "is nil when the flag does not name the app" do
      expect(described_class.for_session(session, config: config, env: {}, speech_keys: speech_keys)).to be_nil
    end

    it "asks the container once for the same user message" do
      allow(Monadic::Utils::ContainerProbe).to receive(:check).and_return({ state: :ready })
      env = { described_class::FLAG => "NotesApp" }
      2.times { described_class.for_session(session, request_id: "q_same", config: config, env: env, speech_keys: speech_keys) }
      described_class.for_session(session, request_id: "q_next", config: config, env: env, speech_keys: speech_keys)
      expect(Monadic::Utils::ContainerProbe).to have_received(:check).twice
    ensure
      Thread.current[described_class::THREAD_KEY] = nil
    end
  end
end
