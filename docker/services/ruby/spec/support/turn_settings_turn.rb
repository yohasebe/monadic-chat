# frozen_string_literal: true

require "json"
require_relative "stream_contract"

# One turn of a chat as a provider is sent it, for the specs of the
# settings a message is answered with: the model calls a tool, the tool
# changes the chat's kept parameters (as a change made on the page while the
# answer runs would), and the model then answers.
module TurnSettingsTurn
  TOOL = { "type" => "function",
           "function" => { "name" => "first_tool", "description" => "t",
                           "parameters" => { "type" => "object", "properties" => {} } } }.freeze

  class ChangingApp
    def initialize(session, change) = (@session, @change = session, change)

    def settings = { "tools" => [TOOL] }

    def first_tool(**)
      @session[:parameters].merge!(@change)
      "done"
    end
  end

  def encode_stream(kind, objects)
    kind == :ndjson ? objects.map { |o| "#{JSON.generate(o)}\n" }.join : objects.map { |o| "data: #{JSON.generate(o)}\n\n" }.join
  end

  # The bodies of the requests of the turn. message: what the message
  # brought; kept: the chat's parameters before it; change: what the tool
  # changes in them.
  # models: the names a provider's own list of models answers with.
  def turn_bodies(helper_module, format:, kind:, key:, message:, kept: {}, change: {}, history: [], models: [])
    helper = Class.new(MonadicApp) { include helper_module }.new
    allow(helper).to receive(:sleep)
    session = { parameters: { "app_name" => "SpecApp", "message" => "What is the weather?", "tools" => [TOOL] }
                            .merge(kept).merge(message),
                messages: [{ "role" => "system", "text" => "S", "active" => true }] + history }
    stub_const("APPS", { "SpecApp" => ChangingApp.new(session, change) })
    stub_const("CONFIG", CONFIG.to_h.merge(key => "k")) if key
    answers = [format.calls([["first_tool", {}]]), format.text(["Done."])].map { |a| encode_stream(kind, a) }
    bodies = []
    chain = double("http")
    %i[timeout headers via].each { |m| allow(chain).to receive(m).and_return(chain) }
    allow(chain).to receive(:post) do |_uri, json:|
      bodies << JSON.parse(JSON.generate(json))
      answer = answers.length > 1 ? answers.shift : answers.first
      body = Object.new.tap do |o|
        o.define_singleton_method(:each) { |&blk| blk.call(answer.dup) }
        o.define_singleton_method(:to_s) { answer.dup }
      end
      double("res", status: HTTP::Response::Status.new(200), body: body, code: 200, headers: {})
    end
    allow(chain).to receive(:get) do
      listed = JSON.generate({ "models" => models.map { |n| { "name" => n } } })
      double("res", status: HTTP::Response::Status.new(200), body: listed, code: 200, headers: {})
    end
    allow(HTTP).to receive(:headers).and_return(chain)
    allow(HTTP).to receive(:timeout).and_return(chain)
    chat = Monadic::Workspace::Ids.generate(:chat)
    session[Monadic::Workspace::Chats::SESSION_KEY] = chat
    context = Monadic::Workspace::RequestContext.new(chat_id: chat,
                                                     settings: Monadic::TurnSettings.accepted(message, kept))
    Monadic::Workspace::RequestContext.with(context) { helper.api_request("user", session) { |_| } }
    bodies
  end
end
