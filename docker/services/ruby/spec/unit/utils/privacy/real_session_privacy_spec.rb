# frozen_string_literal: true

require "spec_helper"
require "rack"
require "rack/session/pool"
require "monadic/library"
require_relative "../../../../lib/monadic/utils/unlimited_session_store"
require_relative "../../../../lib/monadic/agents/second_opinion_agent"
require_relative "../../../../lib/monadic/agents/context_extractor_agent"
require_relative "../../../../lib/monadic/utils/websocket/library_handler"
require_relative "../../../../lib/monadic/utils/websocket/tts_handler"
require_relative "../../../../lib/monadic/utils/websocket/verify_handler"
require_relative "../../../../lib/monadic/mcp/conduit"
require_relative "../../../../lib/monadic/agents/ai_user_agent"

# The Privacy Filter's pipeline lives in the session. The session of a real
# chat is the object the app's session middleware (config.ru) makes, which is
# not a Hash: code that took only a Hash for a session read no pipeline there,
# and sent unmasked text. Each check stops where the text would be masked.
RSpec.describe "Privacy Filter with the session a real chat has" do
  class MaskReached < StandardError; end

  let(:pipeline) { double("Pipeline") }

  # The session object of a request through the same middleware as config.ru.
  def real_session(values)
    made = nil
    inner = lambda do |env|
      made = env["rack.session"]
      values.each { |k, v| made[k] = v }
      [200, {}, ["ok"]]
    end
    Rack::Session::CappedPool.new(inner, key: "monadic.session").call(Rack::MockRequest.env_for("/"))
    made
  end

  it "is a session object that is not a Hash" do
    expect(real_session(_privacy_pipeline: pipeline)).not_to be_a(Hash)
  end

  it "masks the query and answer before a second opinion" do
    agent = Class.new { include SecondOpinionAgent }.new
    allow(agent).to receive(:determine_provider_and_model).and_return(["openai", "test-model"])
    allow(agent).to receive(:get_provider_helper).and_return(Module.new)
    given = nil
    allow(agent).to receive(:mask_for_second_opinion) do |_text, used, _role|
      given = used
      raise MaskReached
    end
    expect do
      agent.second_opinion_agent(user_query: "Email Alice.", agent_response: "Done.",
                                 session: real_session(parameters: {}, _privacy_pipeline: pipeline))
    end.to raise_error(MaskReached)
    expect(given).to be(pipeline)
  end

  it "masks the text before the context is extracted" do
    agent = Class.new { include ContextExtractorAgent }.new
    allow(SystemDefaults).to receive(:get_default_model).and_return("test-model")
    allow(agent).to receive(:get_api_key_for_provider).and_return("test-key-not-sent")
    given = nil
    allow(agent).to receive(:mask_for_extraction) do |_text, used, _role|
      given = used
      raise MaskReached
    end
    # Masking that fails stops the extraction (fail-closed): nothing is sent.
    result = agent.extract_context(real_session(parameters: {}, _privacy_pipeline: pipeline), "Email Alice.", "Done.", "openai")
    expect(given).to be(pipeline)
    expect(result).to be_nil
  end

  it "refuses to save the conversation to the Knowledge Base while the filter is on" do
    replies = []
    host = Class.new { include WebSocketHelper }.new
    host.define_singleton_method(:send_to_client) { |_conn, payload| replies << payload }
    host.send(:handle_ws_library_save, nil, { "contents" => { "messages" => [] } },
              real_session(_privacy_pipeline: pipeline))
    expect(replies.first).to include("type" => "library_saved", "res" => "failure")
    expect(replies.first["content"]).to include("Privacy Filter is active")
  end

  it "stops further tool calls after parallel second opinions" do
    agent = Class.new { include SecondOpinionAgent }.new
    allow(agent).to receive(:second_opinion_agent).and_return({ comments: "ok", validity: "8/10", model: "m" })
    stub_const("CONFIG", CONFIG.merge("OPENAI_API_KEY" => "test-not-sent", "ANTHROPIC_API_KEY" => "test-not-sent"))
    session = real_session(parameters: {})
    agent.parallel_second_opinions(user_query: "q", agent_response: "a", providers: %w[openai anthropic], session: session)
    expect(session[:call_depth_per_turn]).to eq(SecondOpinionAgent::FORCE_STOP_DEPTH)
  end

  describe "when the filter is on but cannot mask, nothing is sent" do
    let(:on_without_pipeline) { real_session(parameters: { "app_name" => "ChatOpenAI" }, _privacy_session_enabled: true) }

    it "decides by the chat's session: masks with its pipeline, sends as is only when the filter is off" do
      outbound = Monadic::Utils::Privacy::Outbound
      expect(outbound.pipeline!(real_session(parameters: {}, _privacy_pipeline: pipeline))).to be(pipeline)
      expect(outbound.pipeline!(real_session(parameters: {}))).to be_nil
      expect(outbound.pipeline!(outbound::NOT_FOR_A_CHAT)).to be_nil # said by a caller not acting for a chat (MCP)
      # A session lost on the way (an argument not passed) is not taken for "not a chat".
      expect { outbound.pipeline!(nil) }.to raise_error(outbound::Refused, /not given/)
      expect { outbound.pipeline!(on_without_pipeline) }.to raise_error(outbound::Refused, /Privacy Filter is on/)
      # The stand-in given where the session was not available (another thread).
      expect { outbound.pipeline!({}) }.to raise_error(outbound::Refused, /could not be read/)
      expect { outbound.pipeline!("text") }.to raise_error(outbound::Refused)
    end

    it "keeps the session readable when it is copied for another thread (as the context extraction is)" do
      copy = real_session(parameters: {}, _privacy_pipeline: pipeline).dup
      expect(Monadic::Utils::Privacy::Outbound.pipeline!(copy)).to be(pipeline)
    end

    it "does not ask for a second opinion" do
      agent = Class.new { include SecondOpinionAgent }.new
      allow(agent).to receive(:determine_provider_and_model).and_return(["openai", "test-model"])
      # The provider is chosen first; nothing is sent to it (an empty helper
      # would fail on any call).
      allow(agent).to receive(:get_provider_helper).and_return(Module.new)
      result = agent.second_opinion_agent(user_query: "Email Alice.", agent_response: "Done.", session: on_without_pipeline)
      expect(result[:validity]).to eq("error")
      expect(result[:comments]).to include("not requested")
    end

    it "extracts no context, also from the empty stand-in session" do
      agent = Class.new { include ContextExtractorAgent }.new
      allow(SystemDefaults).to receive(:get_default_model).and_return("test-model")
      allow(agent).to receive(:get_api_key_for_provider).and_return("test-key-not-sent")
      expect(Net::HTTP).not_to receive(:start)
      expect(agent.extract_context(on_without_pipeline, "Email Alice.", "Done.", "openai")).to be_nil
      expect(agent.extract_context({}, "Email Alice.", "Done.", "openai")).to be_nil
    end

    it "suggests no title for the Knowledge Base" do
      replies = []
      host = Class.new { include WebSocketHelper }.new
      host.define_singleton_method(:send_to_client) { |_conn, payload| replies << payload }
      expect(Monadic::Library::TitleSuggester).not_to receive(:suggest)
      host.send(:handle_ws_library_suggest_title, nil, { "contents" => { "messages" => [{ "role" => "user", "text" => "Hi" }] } },
                on_without_pipeline)
      expect(replies.first).to include("type" => "library_title_suggested", "res" => "failure")
    end

    it "makes no speech" do
      host = Class.new { include WebSocketHelper }.new
      errors = []
      allow(host).to receive(:send_error) { |msg, *_| errors << msg }
      expect(host.send(:privacy_sanitize_tts_text, "Call Alice.", on_without_pipeline)).to be_nil
      expect(errors.first).to include("Speech was not made")
    end
  end

  describe "Verify (the answer re-asked to a panel of other models)" do
    let(:conversation) do
      [{ "mid" => "u1", "role" => "user", "text" => "Email Alice at alice@example.com.", "app_name" => "ChatOpenAI" },
       { "mid" => "a1", "role" => "assistant", "text" => "Sent to alice@example.com.", "app_name" => "ChatOpenAI" }]
    end
    let(:masking) do
      Class.new do
        def before_send_to_llm(raw)
          Struct.new(:text).new(raw.text.gsub("alice@example.com", "<<EMAIL_1>>"))
        end
      end.new
    end

    def verify_with(session)
      host = Class.new { include WebSocketHelper }.new
      replies = []
      host.define_singleton_method(:send_to_client) { |_conn, payload| replies << payload }
      allow(host).to receive(:send_or_broadcast)
      sent = []
      allow(Monadic::MCP::Conduit).to receive(:call) { |_tool, args| sent << args; {} }
      Thread.current[:rack_session] = session
      host.send(:handle_ws_verify_confidence, nil, { "mid" => "a1" }, session)
      sleep 0.2 # the panel runs in its own thread
      [sent, replies]
    ensure
      Thread.current[:rack_session] = nil
    end

    it "sends the panel the conversation masked as the chat's model got it" do
      sent, = verify_with(real_session(parameters: {}, messages: conversation, _privacy_pipeline: masking))
      expect(sent.first["messages"].first["content"]).to eq("Email Alice at <<EMAIL_1>>.")
      expect(sent.first["review_answer"]).to eq("Sent to <<EMAIL_1>>.")
    end

    it "sends nothing when the filter is on but cannot mask" do
      sent, replies = verify_with(real_session(parameters: {}, messages: conversation, _privacy_session_enabled: true))
      expect(sent).to be_empty
      expect(replies.last.to_s).to include("Not verified")
    end
  end

  describe "AI User (a suggestion written by another model)" do
    let(:conversation) do
      [{ "role" => "user", "text" => "Email alice@example.com." }, { "role" => "assistant", "text" => "Done, alice@example.com." }]
    end
    let(:masking) do
      Class.new do
        def before_send_to_llm(raw)
          Struct.new(:text).new(raw.text.gsub("alice@example.com", "<<EMAIL_1>>"))
        end

        def after_receive_from_llm(text)
          Monadic::Utils::Privacy::RestoredResponse.new(text.gsub("<<EMAIL_1>>", "alice@example.com"), {})
        end
      end.new
    end

    def suggest(session)
      agent = Class.new { include AIUserAgent }.new
      sent = []
      app = double("app", send_query: nil)
      allow(app).to receive(:send_query) { |options, **| sent << options; "Thanks, I will write to <<EMAIL_1>>." }
      allow(agent).to receive(:find_chat_app_for_provider).and_return(["ChatOpenAI", app])
      allow(agent).to receive(:default_model_for_provider).and_return("test-model")
      [agent.process_ai_user(session, { "ai_user_provider" => "openai" }), sent]
    end

    it "is asked with the conversation masked, and the suggestion comes back restored" do
      require_relative "../../../../lib/monadic/utils/privacy/types"
      result, sent = suggest(real_session(parameters: {}, messages: conversation, _privacy_pipeline: masking))
      expect(sent.to_s).to include("<<EMAIL_1>>")
      expect(sent.to_s).not_to include("alice@example.com")
      expect(result["content"]).to eq("Thanks, I will write to alice@example.com.")
    end

    it "is not asked when the filter is on but cannot mask" do
      result, sent = suggest(real_session(parameters: {}, messages: conversation, _privacy_session_enabled: true))
      expect(sent).to be_empty
      expect(result["type"]).to eq("error")
    end
  end

  # The Second Opinion apps, called the way a tool call reaches them: each
  # vendor adds the session only when the method names a session parameter.
  describe "the Second Opinion apps, through their own classes" do
    %w[openai claude gemini grok mistral cohere deepseek].each do |vendor|
      it "masks for #{vendor}, with the session the tool call gives" do
        require_relative "../../../../apps/second_opinion/second_opinion_#{vendor}"
        klass = Object.const_get("SecondOpinion#{vendor == 'openai' ? 'OpenAI' : vendor == 'deepseek' ? 'DeepSeek' : vendor.capitalize}")
        app = klass.allocate
        allow(app).to receive(:determine_provider_and_model).and_return([vendor, "test-model"])
        allow(app).to receive(:get_provider_helper).and_return(Module.new)
        given = nil
        allow(app).to receive(:mask_for_second_opinion) do |_text, used, _role|
          given = used
          raise MaskReached
        end

        arguments = { user_query: "Email Alice.", agent_response: "Done." }
        if app.method(:second_opinion_agent).parameters.any? { |_type, name| name == :session }
          arguments[:session] = real_session(parameters: {}, _privacy_pipeline: pipeline)
        end
        app.second_opinion_agent(**arguments)
        expect(given).to be(pipeline)
      end
    end
  end

  # A tab that reconnects or imports a conversation has the filter on but no
  # pipeline yet (a pipeline holds the session it was built for, so it is not
  # carried over). What masks before the chat's own call builds one for this
  # session, keeping the registry; an app without the filter still refuses.
  describe "a chat whose pipeline is not built yet" do
    let(:privacy_app) { double("App", settings: { privacy: { enabled: true } }) }
    let(:plain_app) { double("App", settings: {}) }

    before { stub_const("APPS", { "MailComposerOpenAI" => privacy_app, "ChatOpenAI" => plain_app }) }

    it "gets one built for its own session" do
      registry = { registry: { "Alice" => "<<PERSON_1>>" } }
      session = real_session(parameters: { "app_name" => "MailComposerOpenAI" }, _privacy_session_enabled: true,
                             monadic_state: { privacy: registry })
      pipeline = Monadic::Utils::Privacy::Outbound.pipeline!(session)
      expect(pipeline).to be_a(Monadic::Substitution::Providers::PrivacyFilter)
      expect(pipeline.instance_variable_get(:@session)).to equal(session)
      expect(session[:_privacy_pipeline]).to equal(pipeline)
      expect(session[:monadic_state][:privacy]).to eq(registry)
    end

    it "is refused when its app does not use the filter" do
      session = real_session(parameters: { "app_name" => "ChatOpenAI" }, _privacy_session_enabled: true)
      expect { Monadic::Utils::Privacy::Outbound.pipeline!(session) }
        .to raise_error(Monadic::Utils::Privacy::Outbound::Refused)
    end
  end
end
