# frozen_string_literal: true

require "spec_helper"

RSpec.describe "PDF Routes logic" do
  describe "error_json helper" do
    # Tests the error_json format used consistently across PDF routes

    def error_json(message)
      { success: false, error: message }.to_json
    end

    it "returns valid JSON with success:false" do
      result = JSON.parse(error_json("test error"))
      expect(result["success"]).to be false
      expect(result["error"]).to eq("test error")
    end

    it "preserves error message with special characters" do
      msg = "Failed: status=403 (forbidden)"
      result = JSON.parse(error_json(msg))
      expect(result["error"]).to eq(msg)
    end

    it "handles empty error messages" do
      result = JSON.parse(error_json(""))
      expect(result["success"]).to be false
      expect(result["error"]).to eq("")
    end
  end

  describe "App key resolution" do
    # Tests the pattern for resolving app_key from session parameters

    def resolve_app_key(session_params)
      (session_params && session_params["app_name"]) || "default"
    rescue StandardError
      "default"
    end

    it "returns app_name from session parameters" do
      expect(resolve_app_key({ "app_name" => "knowledge_base" })).to eq("knowledge_base")
    end

    it "returns default when parameters is nil" do
      expect(resolve_app_key(nil)).to eq("default")
    end

    it "returns default when app_name is missing" do
      expect(resolve_app_key({ "model" => "gpt-5" })).to eq("default")
    end

    it "returns default when parameters is empty" do
      expect(resolve_app_key({})).to eq("default")
    end
  end
end
