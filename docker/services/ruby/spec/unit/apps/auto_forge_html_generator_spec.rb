require "spec_helper"
require_relative "../../../apps/auto_forge/agents/html_generator"

RSpec.describe AutoForge::Agents::HtmlGenerator do
  subject(:generator) { described_class.new(context) }

  let(:client_double) { instance_double("CodexClient") }
  let(:context) { { app_instance: client_double, agent: :openai } }
  let(:codex_html) do
    <<~HTML
      <!DOCTYPE html>
      <html>
        <head><title>Codex App</title></head>
        <body><h1>Hello</h1></body>
      </html>
    HTML
  end

  describe "#generate" do
    context "when Codex returns full HTML" do
      before do
        allow(client_double).to receive(:has_gpt5_codex_access?).and_return(true)
        allow(client_double).to receive(:call_gpt5_codex)
          .and_return({ success: true, code: codex_html })
      end

      it "returns the HTML payload" do
        result = generator.generate("Build an app")

        expect(result[:mode]).to eq(:full)
        expect(result[:content]).to include("<!DOCTYPE html>")
      end
    end

    context "when Codex returns a patch" do
      let(:patch_text) do
        <<~PATCH
          --- index.html
          +++ index.html
          @@
          -Old
          +New
        PATCH
      end

      before do
        allow(client_double).to receive(:has_gpt5_codex_access?).and_return(true)
        allow(client_double).to receive(:call_gpt5_codex)
          .and_return({ success: true, code: patch_text })
      end

      it "returns the patch payload" do
        result = generator.generate("Update app", existing_content: "Old", file_name: 'index.html')

        expect(result[:mode]).to eq(:patch)
        expect(result[:patch]).to include('@@')
      end
    end

    context "when Codex fails" do
      before do
        allow(client_double).to receive(:has_gpt5_codex_access?).and_return(true)
        allow(client_double).to receive(:call_gpt5_codex)
          .and_return({ success: false, error: 'timeout' })
      end

      it "returns error mode" do
        result = generator.generate("Build an app")

        expect(result[:mode]).to eq(:error)
        expect(result[:error]).to eq('timeout')
      end
    end

    context "when Codex client is unavailable" do
      let(:context) { {} }  # No app_instance or codex_callback

      it "returns error mode" do
        result = generator.generate("Build an app")

        expect(result[:mode]).to eq(:error)
        expect(result[:error]).to include("integration not available")
      end
    end
  end
end
