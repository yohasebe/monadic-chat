# frozen_string_literal: true

require "json"
require_relative "stream_contract"
require_relative "../../lib/monadic/workbench/picture"

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

  # The bodies of the requests of the turn (where they were sent is left in
  # @turn_uris). message: what the message brought; kept: the chat's
  # parameters before it; change: what the tool changes in them.
  # models: the names a provider's own list of models answers with.
  # answering: the settings of a message of another chat being answered
  # while this request is made (a tool of its reply asks a model of its
  # own); the request then has no message of its own.
  # messages: the messages of a chat to go on from (left in @turn_messages
  # after a turn), in place of a new chat's.
  # failing: how many of the first requests fail on the network, each after
  # the change is made to the chat's kept parameters (their bodies are left
  # in @turn_failed, not among those given back).
  # answers: the model's streams in order, in place of a tool call and then
  # an answer; the last is given again to every later request.
  # picture: bytes of a picture of the work screen the message is sent with
  # (Workbench::Picture, left in @turn_picture).
  def turn_bodies(helper_module, format:, kind:, key:, message:, kept: {}, change: {}, history: [], models: [],
                  answering: nil, messages: nil, failing: 0, answers: nil, picture: nil)
    helper = Class.new(MonadicApp) { include helper_module }.new
    allow(helper).to receive(:sleep)
    session = { parameters: { "app_name" => "SpecApp", "message" => "What is the weather?", "tools" => [TOOL] }
                            .merge(kept).merge(message),
                messages: messages || ([{ "role" => "system", "text" => "S", "active" => true }] + history) }
    @turn_messages = session[:messages]
    stub_const("APPS", { "SpecApp" => ChangingApp.new(session, change) })
    stub_const("CONFIG", CONFIG.to_h.merge(key => "k")) if key
    answers = (answers || [format.calls([["first_tool", {}]]), format.text(["Done."])]).map { |a| encode_stream(kind, a) }
    bodies = []
    @turn_failed = []
    chain = double("http")
    %i[timeout headers via].each { |m| allow(chain).to receive(m).and_return(chain) }
    @turn_uris = []
    allow(chain).to receive(:post) do |uri, json:|
      if @turn_failed.size < failing
        @turn_failed << JSON.parse(JSON.generate(json))
        session[:parameters].merge!(change)
        raise HTTP::ConnectionError, "offline"
      end
      @turn_uris << uri.to_s
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
    @turn_picture = nil
    if picture
      request_id = Monadic::Workspace::Ids.generate(:request)
      @turn_picture = Monadic::Workbench::Picture.new(
        id: "p_#{"a" * 20}", chat_id: chat, request_id: request_id, item_id: "i_1", version: "v" * 64, page: 2, pages: 5,
        mark: { "shape" => "ellipse", "x" => 0.25, "y" => 0.5, "w" => 0.25, "h" => 0.125 }, bytes: picture
      )
    end
    context = if answering
                Monadic::Workspace::RequestContext.new(chat_id: chat, parameters: answering,
                                                       settings: Monadic::TurnSettings.of(answering))
              else
                Monadic::Workspace::RequestContext.new(chat_id: chat, parameters: session[:parameters],
                                                       settings: Monadic::TurnSettings.accepted(message, kept),
                                                       **(@turn_picture ? { request_id: @turn_picture.request_id,
                                                                            picture: @turn_picture } : {}))
              end
    Monadic::Workspace::RequestContext.with(context) { helper.api_request("user", session) { |_| } }
    bodies
  end
end
