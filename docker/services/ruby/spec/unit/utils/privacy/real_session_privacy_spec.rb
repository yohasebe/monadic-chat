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

# The session of a real chat is the object the app's session middleware
# (config.ru) makes, which is not a Hash: what reads a chat's words from it
# must not take only a Hash for a session.
RSpec.describe "A chat's words with the session a real chat has" do
  class HidingReached < StandardError; end

  let(:pipeline) { double("Pipeline") }
  let(:words) { Monadic::Utils::Privacy::Words }

  after { words::LOCK.synchronize { words::TABLES.clear } }

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

  # A real session of a chat whose table holds the words.
  def hiding(values, hidden = [])
    session = real_session({ Monadic::Workspace::Chats::SESSION_KEY => Monadic::Workspace::Ids.generate(:chat) }.merge(values))
    words.start!(session).confirm_all!(hidden)
    session
  end

  # A real session of a chat with the mark whose table is not here.
  def table_lost(values = {})
    chat_id = Monadic::Workspace::Ids.generate(:chat)
    real_session({ parameters: { "app_name" => "ChatOpenAI" }, Monadic::Workspace::Chats::SESSION_KEY => chat_id,
                   words::MARK_KEY => chat_id }.merge(values))
  end

  it "is a session object that is not a Hash" do
    expect(real_session(_privacy_pipeline: pipeline)).not_to be_a(Hash)
  end

  it "hides the words with the session given to a second opinion" do
    agent = Class.new { include SecondOpinionAgent }.new
    allow(agent).to receive(:determine_provider_and_model).and_return(["openai", "test-model"])
    allow(agent).to receive(:get_provider_helper).and_return(Module.new)
    given = nil
    allow(agent).to receive(:second_opinion_words) do |_query, _answer, used|
      given = used
      raise HidingReached
    end
    session = hiding({ parameters: {} }, [%w[Alice PERSON]])
    expect do
      agent.second_opinion_agent(user_query: "Email Alice.", agent_response: "Done.", session: session)
    end.to raise_error(HidingReached)
    expect(given).to be(session)
  end

  it "extracts no context when the words cannot be hidden" do
    agent = Class.new { include ContextExtractorAgent }.new
    allow(SystemDefaults).to receive(:get_default_model).and_return("test-model")
    allow(agent).to receive(:get_api_key_for_provider).and_return("test-key-not-sent")
    allow(words).to receive(:hide_texts).and_raise(StandardError, "not hidden")
    expect(agent).not_to receive(:call_provider_api)
    session = hiding({ parameters: {} }, [%w[Alice PERSON]])
    expect(agent.extract_context(session, "Email Alice.", "Done.", "openai")).to be_nil
  end

  it "refuses to save a chat with a word table to the Knowledge Base" do
    replies = []
    host = Class.new { include WebSocketHelper }.new
    host.define_singleton_method(:send_to_client) { |_conn, payload| replies << payload }
    session = real_session(Monadic::Workspace::Chats::SESSION_KEY => "chat-1")
    Monadic::Utils::Privacy::Words.start!(session)
    host.send(:handle_ws_library_save, nil, { "contents" => { "messages" => [] } }, session)
    expect(replies.first).to include("type" => "library_saved", "res" => "failure")
    expect(replies.first["content"]).to include("hides words")
  end

  it "stops further tool calls after parallel second opinions" do
    agent = Class.new { include SecondOpinionAgent }.new
    allow(agent).to receive(:second_opinion_agent).and_return({ comments: "ok", validity: "8/10", model: "m" })
    stub_const("CONFIG", CONFIG.merge("OPENAI_API_KEY" => "test-not-sent", "ANTHROPIC_API_KEY" => "test-not-sent"))
    session = real_session(parameters: {})
    agent.parallel_second_opinions(user_query: "q", agent_response: "a", providers: %w[openai anthropic], session: session)
    expect(session[:call_depth_per_turn]).to eq(SecondOpinionAgent::FORCE_STOP_DEPTH)
  end

  describe "when the words cannot be hidden, nothing is sent" do
    # The table is gone, and the empty stand-in given where the session was
    # not available.
    [["a chat whose table is lost", :table_lost], ["an empty stand-in session", :stand_in]].each do |label, kind|
      context "for #{label}" do
        let(:session) { kind == :stand_in ? {} : table_lost }

        it "does not ask for a second opinion" do
          agent = Class.new { include SecondOpinionAgent }.new
          allow(agent).to receive(:determine_provider_and_model).and_return(["openai", "test-model"])
          # The provider is chosen first; nothing is sent to it (an empty helper
          # would fail on any call).
          allow(agent).to receive(:get_provider_helper).and_return(Module.new)
          result = agent.second_opinion_agent(user_query: "Email Alice.", agent_response: "Done.", session: session)
          expect(result[:validity]).to eq("error")
          expect(result[:comments]).to include("not requested")
        end

        it "extracts no context" do
          agent = Class.new { include ContextExtractorAgent }.new
          allow(SystemDefaults).to receive(:get_default_model).and_return("test-model")
          allow(agent).to receive(:get_api_key_for_provider).and_return("test-key-not-sent")
          expect(agent).not_to receive(:call_provider_api)
          expect(agent.extract_context(session, "Email Alice.", "Done.", "openai")).to be_nil
        end

        it "suggests no title for the Knowledge Base" do
          replies = []
          host = Class.new { include WebSocketHelper }.new
          host.define_singleton_method(:send_to_client) { |_conn, payload| replies << payload }
          expect(Monadic::Library::TitleSuggester).not_to receive(:suggest)
          host.send(:handle_ws_library_suggest_title, nil, { "contents" => { "messages" => [{ "role" => "user", "text" => "Hi" }] } },
                    session)
          expect(replies.first).to include("type" => "library_title_suggested", "res" => "failure")
        end

        it "makes no speech" do
          host = Class.new { include WebSocketHelper }.new
          errors = []
          allow(host).to receive(:send_error) { |msg, *_| errors << msg }
          expect(host.send(:privacy_sanitize_tts_text, "Call Alice.", session)).to be_nil
          expect(errors.first).to include("Speech was not made")
        end
      end
    end

    it "tells a lost or unreadable session from a caller that acts for no chat" do
      outbound = Monadic::Utils::Privacy::Outbound
      expect { outbound.chat_session!(real_session(parameters: {})) }.not_to raise_error
      expect { outbound.chat_session!(outbound::NOT_FOR_A_CHAT) }.not_to raise_error # said by a caller not acting for a chat (MCP)
      # A session lost on the way (an argument not passed) is not taken for "not a chat".
      expect { outbound.chat_session!(nil) }.to raise_error(outbound::Refused, /not given/)
      # The stand-in given where the session was not available (another thread).
      expect { outbound.chat_session!({}) }.to raise_error(outbound::Refused, /could not be read/)
      expect { outbound.chat_session!("text") }.to raise_error(outbound::Refused)
    end

    it "keeps the session readable when it is copied for another thread (as the context extraction is)" do
      copy = real_session(parameters: {}).dup
      expect { Monadic::Utils::Privacy::Outbound.chat_session!(copy) }.not_to raise_error
    end
  end

  describe "Verify (the answer re-asked to a panel of other models)" do
    let(:conversation) do
      [{ "mid" => "u1", "role" => "user", "text" => "Email Alice at alice@example.com.", "app_name" => "ChatOpenAI" },
       { "mid" => "a1", "role" => "assistant", "text" => "Sent to alice@example.com.", "app_name" => "ChatOpenAI" }]
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

    it "sends the panel the conversation hidden as the chat's model got it" do
      sent, = verify_with(hiding({ parameters: {}, messages: conversation }, [%w[alice@example.com EMAIL_ADDRESS]]))
      expect(sent.first["messages"].first["content"]).to eq("Email Alice at <<EMAIL_ADDRESS_1>>.")
      expect(sent.first["review_answer"]).to eq("Sent to <<EMAIL_ADDRESS_1>>.")
    end

    it "sends nothing when the words cannot be hidden" do
      sent, replies = verify_with(table_lost(messages: conversation))
      expect(sent).to be_empty
      expect(replies.last.to_s).to include("Not verified")
    end
  end

  describe "AI User (a suggestion written by another model)" do
    let(:conversation) do
      [{ "role" => "user", "text" => "Email alice@example.com." }, { "role" => "assistant", "text" => "Done, alice@example.com." }]
    end
    def suggest(session)
      agent = Class.new { include AIUserAgent }.new
      sent = []
      app = double("app", send_query: nil)
      allow(app).to receive(:send_query) { |options, **| sent << options; "Thanks, I will write to <<EMAIL_ADDRESS_1>>." }
      allow(agent).to receive(:find_chat_app_for_provider).and_return(["ChatOpenAI", app])
      allow(agent).to receive(:default_model_for_provider).and_return("test-model")
      [agent.process_ai_user(session, { "ai_user_provider" => "openai" }), sent]
    end

    it "is asked with the conversation hidden, and the suggestion comes back with the word" do
      result, sent = suggest(hiding({ parameters: {}, messages: conversation }, [%w[alice@example.com EMAIL_ADDRESS]]))
      expect(sent.to_s).to include("<<EMAIL_ADDRESS_1>>")
      expect(sent.to_s).not_to include("alice@example.com")
      expect(result["content"]).to eq("Thanks, I will write to alice@example.com.")
    end

    it "is not asked when the words cannot be hidden" do
      result, sent = suggest(table_lost(messages: conversation))
      expect(sent).to be_empty
      expect(result["type"]).to eq("error")
    end

    it "is not asked when the chat's session cannot be read" do
      outbound = Monadic::Utils::Privacy::Outbound
      allow(outbound).to receive(:chat_session!).and_raise(outbound::Refused, "the chat's session could not be read")
      result, sent = suggest(real_session(parameters: {}, messages: conversation))
      expect(sent).to be_empty
      expect(result["type"]).to eq("error")
    end
  end

  # The Second Opinion apps, called the way a tool call reaches them: each
  # vendor adds the session only when the method names a session parameter.
  describe "the Second Opinion apps, through their own classes" do
    %w[openai claude gemini grok mistral cohere deepseek].each do |vendor|
      it "hides the words for #{vendor}, with the session the tool call gives" do
        require_relative "../../../../apps/second_opinion/second_opinion_#{vendor}"
        klass = Object.const_get("SecondOpinion#{vendor == 'openai' ? 'OpenAI' : vendor == 'deepseek' ? 'DeepSeek' : vendor.capitalize}")
        app = klass.allocate
        allow(app).to receive(:determine_provider_and_model).and_return([vendor, "test-model"])
        allow(app).to receive(:get_provider_helper).and_return(Module.new)
        given = nil
        allow(app).to receive(:second_opinion_words) do |_query, _answer, used|
          given = used
          raise HidingReached
        end

        session = hiding({ parameters: {} }, [%w[Alice PERSON]])
        arguments = { user_query: "Email Alice.", agent_response: "Done." }
        if app.method(:second_opinion_agent).parameters.any? { |_type, name| name == :session }
          arguments[:session] = session
        end
        app.second_opinion_agent(**arguments)
        expect(given).to be(session)
      end
    end
  end
end
