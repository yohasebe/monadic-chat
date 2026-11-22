# frozen_string_literal: true

require_relative "../../spec_helper"
require_relative "../../../lib/monadic/shared_tools/monadic_session_state"

RSpec.describe "Monadic::SharedTools::MonadicSessionState" do
  let(:instance) { Class.new { include Monadic::SharedTools::MonadicSessionState }.new }
  let(:chat) { Monadic::Workspace::Ids.generate(:chat) }
  let(:session) do
    { Monadic::Workspace::Chats::SESSION_KEY => chat, messages: [], parameters: { "app_name" => "TestApp" } }
  end

  before do
    Monadic::TurnState.reset!
    @reply = nil
    allow(Monadic::Workbench::Caller).to receive(:current) { @reply }
  end

  # A reply of the chat running now.
  def run_reply
    @reply = Monadic::Workbench::Caller.new(chat_id: chat, epoch: Monadic::Workspace::Chats.epoch(chat),
                                            request_id: Monadic::Workspace::Ids.generate(:request), session: session)
  end

  describe "#monadic_load_state" do
    it "returns the value the chat began with" do
      session[:monadic_state] = {
        "TestApp" => { "my_key" => { data: [1, 2, 3], version: 2, updated_at: "2026-01-01T00:00:00Z" } }
      }

      result = JSON.parse(instance.monadic_load_state(key: "my_key", session: session))
      expect(result).to include("success" => true, "data" => [1, 2, 3], "version" => 2)
    end

    it "returns default when key is missing" do
      result = JSON.parse(instance.monadic_load_state(key: "missing", default: "fallback", session: session))
      expect(result["data"]).to eq("fallback")
    end

    it "fails for an empty key" do
      expect(JSON.parse(instance.monadic_load_state(key: "", session: session))["success"]).to be false
    end
  end

  describe "#monadic_save_state" do
    it "saves the value for the running reply to read back" do
      run_reply
      result = JSON.parse(instance.monadic_save_state(key: "images", payload: ["img.png"], session: session))

      expect(result["success"]).to be true
      expect(JSON.parse(instance.monadic_load_state(key: "images", session: session))["data"]).to eq(["img.png"])
    end

    it "saves nothing without a running reply, and says so" do
      result = JSON.parse(instance.monadic_save_state(key: "k", payload: "v", session: session))

      expect(result["success"]).to be false
      expect(JSON.parse(instance.monadic_load_state(key: "k", session: session))["data"]).to be_nil
    end

    it "saves nothing under another app's name" do
      run_reply
      result = JSON.parse(instance.monadic_save_state(app: "Other", key: "k", payload: "v", session: session))

      expect(result["success"]).to be false
    end

    it "fails when session is nil" do
      expect(JSON.parse(instance.monadic_save_state(key: "k", payload: "v", session: nil))["success"]).to be false
    end
  end
end
