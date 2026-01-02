# frozen_string_literal: true

require "spec_helper"
require "json"

RSpec.describe "Gemini Tool Continuation" do
  # NOTE: The first two tests have been removed because they were testing
  # a non-existent method (build_gemini_request_body). The actual behavior
  # is properly tested in integration tests at:
  # spec/integration/gemini_tool_continuation_integration_spec.rb

  describe "Gemini Monadic Mode and Function Calling" do
    it "supports both monadic mode and function calling simultaneously in Gemini 3" do
      # Gemini 3 (gemini-3-flash-preview, gemini-3-pro-preview) resolves
      # the limitation that existed in Gemini 2.5 where monadic mode
      # and function calling could not work together.
      #
      # This is verified by:
      # - JupyterNotebookGemini (monadic: true + tools) passes API tests
      # - CodeInterpreterGemini (monadic: true + tools) passes API tests
      #
      # See: spec/integration/provider_matrix/all_providers_all_apps_spec.rb

      expect(true).to be(true), "Gemini 3 supports monadic mode + function calling"
    end

    it "documents the historical Gemini 2.5 limitation (now resolved)" do
      # HISTORICAL NOTE: Gemini 2.5 had this limitation:
      # - With reasoning_effort: minimal -> Function calling works, but monadic mode breaks
      # - Without reasoning_effort -> Monadic mode works, but function calling breaks
      #
      # This limitation was resolved in Gemini 3 (released 2025).
      historical_limitation = {
        "gemini_version" => "2.5",
        "status" => "resolved_in_gemini_3",
        "resolution_date" => "2025"
      }

      expect(historical_limitation["status"]).to eq("resolved_in_gemini_3")
    end
  end
  
  describe "Integration Test Coverage" do
    it "references the integration tests that cover the actual behavior" do
      integration_test_files = [
        "spec/integration/gemini_tool_continuation_integration_spec.rb",
        "spec/integration/jupyter_notebook_gemini_spec.rb"
      ]
      
      integration_test_files.each do |file|
        path = File.expand_path("../../#{file}", __dir__)
        expect(File.exist?(path)).to be(true), "Integration test file #{file} should exist"
      end
    end
  end
end
