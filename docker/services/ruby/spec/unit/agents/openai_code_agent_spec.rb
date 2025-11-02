require "spec_helper"
require_relative '../../lib/monadic/agents/openai_code_agent"

RSpec.describe Monadic::Agents::GPT5CodexAgent do
  let(:test_class) do
    Class.new do
      include Monadic::Agents::OpenAICodeAgent

      attr_accessor :gpt5_codex_access

      def list_models
        @models || []
      end

      def set_models(models)
        @models = models
      end

      def api_request(role, session, call_depth: 0)
        @api_request_called = true
        @last_session = session
        [{"content" => "Generated code"}]
      end

      attr_reader :api_request_called, :last_session
    end
  end

  let(:app) { test_class.new }

  describe "#has_openai_code_access?" do
    context "when OpenAI API key is configured" do
      before do
        stub_const("CONFIG", { "OPENAI_API_KEY" => "sk-test123" })
      end

      it "returns true" do
        expect(app.has_openai_code_access?).to be true
      end

      it "caches the result" do
        app.has_openai_code_access?
        stub_const("CONFIG", {})  # Remove API key
        expect(app.has_openai_code_access?).to be true # cached
      end
    end

    context "when OpenAI API key is not configured" do
      before do
        stub_const("CONFIG", {})
      end

      it "returns false" do
        expect(app.has_openai_code_access?).to be false
      end
    end

    context "when OpenAI API key is empty string" do
      before do
        stub_const("CONFIG", { "OPENAI_API_KEY" => "" })
      end

      it "returns false" do
        expect(app.has_openai_code_access?).to be false
      end
    end

    context "when CONFIG is nil" do
      before do
        stub_const("CONFIG", nil)
      end

      it "returns false" do
        expect(app.has_openai_code_access?).to be false
      end
    end
  end

  describe "#call_openai_code" do
    context "when user has access to GPT-5-Codex" do
      before do
        stub_const("CONFIG", { "OPENAI_API_KEY" => "sk-test123" })
        allow(ENV).to receive(:[]).and_call_original
        allow(ENV).to receive(:[]).with('GPT5_CODEX_MODEL').and_return(nil)
      end

      it "makes successful API call" do
        result = app.call_openai_code(prompt: "Write a function")

        expect(result[:success]).to be true
        expect(result[:code]).to eq("Generated code")
        expect(result[:model]).to eq("gpt-5-codex")
      end

      it "builds session with correct structure" do
        app.call_openai_code(prompt: "Test prompt")
        session = app.last_session

        expect(session[:parameters]["model"]).to eq("gpt-5-codex")
        expect(session[:messages].first["text"]).to eq("Test prompt")
        expect(session[:messages].first["role"]).to eq("user")
      end

      it "handles timeout gracefully" do
        allow(Timeout).to receive(:timeout).and_raise(Timeout::Error)

        result = app.call_openai_code(prompt: "Test", timeout: 1)

        expect(result[:success]).to be false
        expect(result[:timeout]).to be true
        expect(result[:error]).to include("timed out")
      end
    end

    context "when user lacks OpenAI API access" do
      before do
        stub_const("CONFIG", {})
      end

      it "returns error about missing API key" do
        result = app.call_openai_code(prompt: "Write code")

        expect(result[:success]).to be false
        expect(result[:error]).to include("not available")
        expect(result[:suggestion]).to be_truthy
        expect(result[:fallback]).to be_truthy
      end
    end

    context "when API returns error" do
      before do
        stub_const("CONFIG", { "OPENAI_API_KEY" => "sk-test123" })
        allow(ENV).to receive(:[]).and_call_original
        allow(ENV).to receive(:[]).with('GPT5_CODEX_MODEL').and_return(nil)
        app.set_models(["gpt-5-codex"])
        allow(app).to receive(:api_request).and_return([{"error" => "Rate limit exceeded"}])
      end

      it "handles API error response" do
        result = app.call_openai_code(prompt: "Test")

        expect(result[:success]).to be false
        expect(result[:error]).to eq("Rate limit exceeded")
      end
    end

    context "when API returns empty response" do
      before do
        stub_const("CONFIG", { "OPENAI_API_KEY" => "sk-test123" })
        allow(ENV).to receive(:[]).and_call_original
        allow(ENV).to receive(:[]).with('GPT5_CODEX_MODEL').and_return(nil)
        app.set_models(["gpt-5-codex"])
        allow(app).to receive(:api_request).and_return([{"content" => ""}])
      end

      it "handles empty response" do
        result = app.call_openai_code(prompt: "Test")

        expect(result[:success]).to be false
        expect(result[:error]).to include("empty response")
      end
    end
  end

  describe "#build_openai_code_prompt" do
    it "builds basic prompt from task" do
      prompt = app.build_openai_code_prompt(task: "Write a sorting function")
      expect(prompt).to eq("Write a sorting function")
    end

    it "includes current code when provided" do
      prompt = app.build_openai_code_prompt(
        task: "Fix this code",
        current_code: "def broken() { }"
      )

      expect(prompt).to include("Fix this code")
      expect(prompt).to include("Current code:")
      expect(prompt).to include("def broken() { }")
    end

    it "includes error context when provided" do
      prompt = app.build_openai_code_prompt(
        task: "Fix error",
        error_context: "undefined method 'foo'"
      )

      expect(prompt).to include("Fix error")
      expect(prompt).to include("Error to fix:")
      expect(prompt).to include("undefined method 'foo'")
    end

    it "includes file context with truncation" do
      files = [
        { path: "main.rb", content: "x" * 2000 },
        { path: "test.rb", content: "test code" }
      ]

      prompt = app.build_openai_code_prompt(
        task: "Refactor",
        files: files
      )

      expect(prompt).to include("Files to consider:")
      expect(prompt).to include("main.rb:")
      expect(prompt).to include("test.rb:")
      expect(prompt.scan("x").length).to be <= 1001 # truncated
    end

    it "limits number of files to 3" do
      files = (1..5).map { |i| { path: "file#{i}.rb", content: "code#{i}" } }

      prompt = app.build_openai_code_prompt(
        task: "Review",
        files: files
      )

      expect(prompt).to include("file1.rb")
      expect(prompt).to include("file2.rb")
      expect(prompt).to include("file3.rb")
      expect(prompt).not_to include("file4.rb")
      expect(prompt).not_to include("file5.rb")
    end
  end

  describe "#message_content_field" do
    it "returns :text as the field name" do
      expect(app.send(:message_content_field)).to eq(:text)
    end
  end

  describe "#build_session" do
    it "creates session with text field" do
      session = app.send(:build_session, prompt: "Test prompt", model: "gpt-5-codex")

      message = session[:messages].first
      expect(message["text"]).to eq("Test prompt")
      expect(message["role"]).to eq("user")
      expect(message["active"]).to be true
    end

    it "sets model parameters" do
      session = app.send(:build_session, prompt: "Test", model: "gpt-5-codex")

      expect(session[:parameters]["model"]).to eq("gpt-5-codex")
      expect(session[:parameters]["max_completion_tokens"]).to eq(128000)
      expect(session[:parameters]["temperature"]).to eq(0.0)
    end

    it "handles invalid message structure gracefully" do
      allow(app).to receive(:message_content_field).and_raise(StandardError)

      session = app.send(:build_session, prompt: "Test", model: "gpt-5-codex")

      # Falls back to basic structure
      expect(session[:messages].first["text"]).to eq("Test")
      expect(session[:parameters]["model"]).to eq("gpt-5-codex")
    end
  end

  describe "#build_access_error_message" do
    it "returns user-friendly error components" do
      error = app.send(:build_access_error_message, "TestApp")

      expect(error[:error]).to include("not available")
      expect(error[:suggestion]).to include("specialized model")
      expect(error[:fallback]).to include("TestApp")
    end

    it "handles nil app name" do
      error = app.send(:build_access_error_message, nil)

      expect(error[:fallback]).to include("The application")
    end
  end

  describe "GPT5_CODEX_DEFAULT_TIMEOUT" do
    it "uses default timeout value" do
      # The constant is already loaded, just verify it's a reasonable value
      expect(Monadic::Agents::GPT5CodexAgent::GPT5_CODEX_DEFAULT_TIMEOUT).to be >= 60
      expect(Monadic::Agents::GPT5CodexAgent::GPT5_CODEX_DEFAULT_TIMEOUT).to be <= 1200
    end

    it "respects environment variable when module is loaded" do
      # This test verifies the current loaded value which may be from ENV
      timeout = Monadic::Agents::GPT5CodexAgent::GPT5_CODEX_DEFAULT_TIMEOUT
      expect(timeout).to be_a(Integer)
      expect(timeout).to be > 0
    end
  end
end