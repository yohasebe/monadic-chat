# frozen_string_literal: true

require "spec_helper"
require_relative "../../../lib/monadic/agents/second_opinion_agent"
require_relative "../../../lib/monadic/utils/privacy/words"

# A second opinion asked in a chat that hides its words with a word table:
# what each provider is sent, and what the comments are put back with.
RSpec.describe "A second opinion in a chat with a word table" do
  let(:words) { Monadic::Utils::Privacy::Words }
  let(:session) { {}.tap { |s| Monadic::Workspace::Chats.start_new!(s) } }
  let(:table) { words.start!(session) }
  let(:agent) { Class.new { include SecondOpinionAgent }.new }
  let(:sent) { Queue.new }

  before { table.confirm!("Ada Lovelace", "PERSON") }
  after { words::LOCK.synchronize { words::TABLES.clear } }

  def evaluator(reply)
    queue = sent
    Object.new.tap do |helper|
      helper.define_singleton_method(:send_query) do |parameters, model: nil|
        queue << parameters["messages"].first["content"]
        reply.respond_to?(:call) ? reply.call : reply
      end
    end
  end

  def comments(text)
    "### COMMENTS\n#{text}\n\n### VALIDITY\n8/10"
  end

  def sent_texts
    Array.new(sent.size) { sent.pop }
  end

  # The tool is called while the model's request is being answered: what
  # the model wrote holds the placeholders of that request.
  def answering
    words.request do
      words.sent_with(table.snapshot)
      yield
    end
  end

  it "sends what the model wrote with the words hidden as they are now, and puts the comments back" do
    allow(agent).to receive(:get_provider_helper).and_return(evaluator(comments("<<PERSON_1>> and <<PERSON_2>> are right.")))
    result = answering do
      table.confirm!("Grace Hopper", "PERSON")
      agent.second_opinion_agent(user_query: "Who was <<PERSON_1>>?",
                                 agent_response: "<<PERSON_1>> worked with Grace Hopper; <<PERSON_2>> is not known.",
                                 provider: "openai", session: session)
    end
    text = sent_texts.join
    expect(text).to include("Who was <<PERSON_1>>?", "<<PERSON_1>> worked with <<PERSON_2>>;")
    expect(text).not_to include("Ada Lovelace", "Grace Hopper", "; <<PERSON_2>> is not known")
    expect(result[:comments]).to start_with("Ada Lovelace and Grace Hopper are right.")
  end

  it "sends nothing once the words change while it is being sent" do
    allow(agent).to receive(:get_provider_helper).and_return(evaluator(lambda {
      table.confirm!("Grace Hopper", "PERSON")
      words.check_sending!
      comments("late")
    }))
    result = answering do
      agent.second_opinion_agent(user_query: "Who was <<PERSON_1>>?", agent_response: "A mathematician.",
                                 provider: "openai", session: session)
    end
    expect(result[:validity]).to eq("error")
    expect(result[:comments]).to include("changed while the request was being sent")
  end

  it "hides the words once for every provider asked, and puts each one's comments back" do
    stub_const("CONFIG", CONFIG.merge("OPENAI_API_KEY" => "test-not-sent", "ANTHROPIC_API_KEY" => "test-not-sent"))
    allow(agent).to receive(:get_provider_helper).and_return(evaluator(comments("<<PERSON_1>> is right.")))
    expect(agent).to receive(:second_opinion_words).once.and_call_original
    result = answering do
      agent.parallel_second_opinions(user_query: "Who was <<PERSON_1>>?", agent_response: "A mathematician.",
                                     providers: %w[openai claude], session: session)
    end
    texts = sent_texts
    expect(texts.size).to eq(2)
    expect(texts).to all(include("Who was <<PERSON_1>>?"))
    expect(result.scan("Ada Lovelace is right.").size).to eq(2)
  end

  it "does not put back a placeholder of a word hidden after the comments were asked for" do
    allow(agent).to receive(:get_provider_helper).and_return(evaluator(lambda {
      table.confirm!("Grace Hopper", "PERSON")
      comments("<<PERSON_1>> and <<PERSON_2>>")
    }))
    result = answering do
      agent.second_opinion_agent(user_query: "Who was <<PERSON_1>>?", agent_response: "A mathematician.",
                                 provider: "openai", session: session)
    end
    expect(result[:comments]).to start_with("Ada Lovelace and <<PERSON_2>>")
  end

  it "sends the placeholders the model wrote outside a request as text, not as the chat's" do
    allow(agent).to receive(:get_provider_helper).and_return(evaluator(comments("ok")))
    agent.second_opinion_agent(user_query: "Who was <<PERSON_1>>?", agent_response: "Ada Lovelace.",
                               provider: "openai", session: session)
    text = sent_texts.join
    expect(text).to include("Who was ‹‹PERSON_1››?", "<<PERSON_1>>.")
    expect(text).not_to include("Ada Lovelace")
  end

  it "keeps the words of two chats apart when both ask for comments at once" do
    other = {}.tap { |s| Monadic::Workspace::Chats.start_new!(s) }
    words.start!(other).confirm!("Grace Hopper", "PERSON")
    allow(agent).to receive(:get_provider_helper).and_return(evaluator(comments("<<PERSON_1>> is right.")))
    results = [[session, "Ada Lovelace"], [other, "Grace Hopper"]].map do |chat, name|
      Thread.new do
        agent.second_opinion_agent(user_query: "Who was #{name}?", agent_response: "A pioneer.",
                                   provider: "openai", session: chat)
      end
    end.map(&:value)
    expect(sent_texts).to all(include("Who was <<PERSON_1>>?"))
    expect(results.map { |r| r[:comments].lines.first.strip }).to eq(["Ada Lovelace is right.", "Grace Hopper is right."])
  end

  it "sends nothing when the chat's table is not there" do
    allow(agent).to receive(:get_provider_helper).and_return(evaluator(comments("ok")))
    words::LOCK.synchronize { words::TABLES.clear }
    result = agent.second_opinion_agent(user_query: "q", agent_response: "a", provider: "openai", session: session)
    expect(result[:validity]).to eq("error")
    expect(sent).to be_empty
  end

  it "sends what a request that belongs to no chat gives as it is" do
    allow(agent).to receive(:get_provider_helper).and_return(evaluator(comments("<<PERSON_1>> is right.")))
    result = agent.second_opinion_agent(user_query: "Who was Ada Lovelace?", agent_response: "<<PERSON_1>>",
                                        provider: "openai",
                                        session: Monadic::Utils::Privacy::Outbound::NOT_FOR_A_CHAT)
    expect(sent_texts.join).to include("Who was Ada Lovelace?")
    expect(result[:comments]).to start_with("<<PERSON_1>> is right.")
  end
end
