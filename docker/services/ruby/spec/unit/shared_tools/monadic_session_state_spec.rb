# frozen_string_literal: true

require_relative "../../spec_helper"
require_relative "../../../lib/monadic/shared_tools/monadic_session_state"

RSpec.describe "Monadic::SharedTools::MonadicSessionState" do
  let(:test_class) do
    Class.new do
      include Monadic::SharedTools::MonadicSessionState
    end
  end
  let(:instance) { test_class.new }

  describe "#monadic_load_state" do
    it "returns data from session monadic_state" do
      session = {
        monadic_state: {
          "TestApp" => {
            "my_key" => { data: [1, 2, 3], version: 2, updated_at: "2026-01-01T00:00:00Z" }
          }
        },
        parameters: { "app_name" => "TestApp" }
      }

      result = JSON.parse(instance.monadic_load_state(key: "my_key", session: session))
      expect(result["success"]).to be true
      expect(result["data"]).to eq([1, 2, 3])
      expect(result["version"]).to eq(2)
    end

    it "returns default when key is missing" do
      session = { monadic_state: {}, parameters: { "app_name" => "TestApp" } }
      result = JSON.parse(instance.monadic_load_state(key: "missing", default: "fallback", session: session))
      expect(result["data"]).to eq("fallback")
    end

    it "raises error for empty key" do
      session = { parameters: { "app_name" => "TestApp" } }
      result = JSON.parse(instance.monadic_load_state(key: "", session: session))
      expect(result["success"]).to be false
    end
  end

  describe "#monadic_save_state" do
    it "saves data to session monadic_state" do
      session = { parameters: { "app_name" => "TestApp" } }
      result = JSON.parse(instance.monadic_save_state(key: "images", payload: ["img.png"], session: session))
      expect(result["success"]).to be true
      expect(result["version"]).to eq(1)
      expect(session[:monadic_state]["TestApp"]["images"][:data]).to eq(["img.png"])
    end

    it "increments version on subsequent saves" do
      session = { parameters: { "app_name" => "TestApp" } }
      instance.monadic_save_state(key: "k", payload: "v1", session: session)
      result = JSON.parse(instance.monadic_save_state(key: "k", payload: "v2", session: session))
      expect(result["version"]).to eq(2)
    end

    it "raises error when session is nil" do
      result = JSON.parse(instance.monadic_save_state(key: "k", payload: "v", session: nil))
      expect(result["success"]).to be false
    end
  end

end
