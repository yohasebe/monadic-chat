# frozen_string_literal: true

require "spec_helper"
require "json"
require "tmpdir"
require_relative "../../../apps/mermaid_grapher/mermaid_grapher_tools"

# Verifies that preview_mermaid treats a browser-side render error as a failure
# instead of presenting Mermaid's error graphic as a finished diagram.
#
# Background (2026-06-02 follow-up): the preview path pre-validates with a
# lenient static check (run_full_validation source: :preview_tool) and then
# screenshots whatever the browser drew. Mermaid emits an <svg> even on a parse
# failure (the "bomb" icon, aria-roledescription="error"), so a passing static
# check followed by a successful screenshot reported success while the user saw
# an error. The new check_render_error web_navigator action is consulted between
# render and screenshot; these specs pin that the result gates the response.
RSpec.describe "MermaidGrapherTools#preview_mermaid render-error gating" do
  let(:test_class) do
    Class.new do
      include MermaidGrapherTools

      attr_reader :commands

      def initialize
        @commands = []
      end

      # Static pre-validation always passes here; we are exercising the
      # post-render error gate, not the static validator.
      def run_full_validation(_code, source: nil)
        { success: true, workflow_status: "validation_passed" }
      end

      def mermaid_session_active?
        false
      end

      # Stand-in for the Docker exec bridge. Returns canned JSON per action.
      def send_command(command:, container:)
        @commands << command
        if command.include?("--action start")
          '{"success": true}'
        elsif command.include?("--action check_render_error")
          @render_error_json
        elsif command.include?("--action full_screenshot")
          # Stub the capture as unavailable so the test does not depend on
          # screenshot post-processing (file copy / SVG trimming). Reaching this
          # command at all is what proves the render-error gate let the diagram
          # through; the screenshot machinery itself is out of scope here.
          '{"success": false, "error": "capture stubbed"}'
        else
          '{"success": true}'
        end
      end

      def stub_render_error(json)
        @render_error_json = json
      end
    end
  end

  let(:tools) { test_class.new }
  let(:code) { "mindmap\n  root((化学))\n    分析化学\n      クロマトグラフィー\n" }

  before do
    # Avoid touching the real shared volume / filesystem.
    allow(Monadic::Utils::Environment).to receive(:shared_volume).and_return(Dir.mktmpdir)
  end

  context "when the browser rendered Mermaid's error graphic" do
    it "returns a failure with the render-error detail and skips the screenshot" do
      tools.stub_render_error('{"success": true, "render_error": true, "error_text": "Syntax error in text"}')

      response = JSON.parse(tools.preview_mermaid(code: code))

      expect(response["success"]).to be false
      expect(response["error"].to_s).to include("Diagram render error")
      expect(response["error"].to_s).to include("Syntax error in text")
      expect(tools.commands).to include(a_string_matching(/check_render_error/))
      expect(tools.commands).not_to include(a_string_matching(/full_screenshot/))
    end

    it "falls back to a generic message when error_text is blank" do
      tools.stub_render_error('{"success": true, "render_error": true, "error_text": ""}')

      response = JSON.parse(tools.preview_mermaid(code: code))

      expect(response["success"]).to be false
      expect(response["error"].to_s).to include("Diagram render error")
    end
  end

  context "when the browser rendered a real diagram" do
    it "passes the render-error gate and proceeds to capture the screenshot" do
      tools.stub_render_error('{"success": true, "render_error": false, "error_text": null}')

      response = JSON.parse(tools.preview_mermaid(code: code))

      # The gate must let a clean render through to the screenshot step. The
      # final payload's success depends on screenshot post-processing (file I/O)
      # which is out of scope here; what this case pins is that render_error=false
      # does NOT short-circuit into a "Diagram render error" failure.
      expect(tools.commands).to include(a_string_matching(/full_screenshot/))
      expect(response["error"].to_s).not_to include("Diagram render error")
    end
  end
end
