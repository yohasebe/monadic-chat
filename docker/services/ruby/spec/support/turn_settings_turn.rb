# frozen_string_literal: true

require "json"
require_relative "stream_contract"
require_relative "../../lib/monadic/workbench/picture"
require_relative "../../lib/monadic/workbench/selection"

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

  # The item and version a picture in these turns is of.
  PICTURED_ITEM = "i_pictureditem0q7"
  PICTURED_VERSION = "f0e1d2c3" * 8

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
  # (Workbench::Picture, left in @turn_picture); picture_chat: the chat it was
  # taken for, when not the session's. selection: text the user selected in
  # the work screen to send with the message (Workbench::Selection). hidden:
  # words the chat hides (its word table).
  def turn_bodies(helper_module, format:, kind:, key:, message:, kept: {}, change: {}, history: [], models: [],
                  answering: nil, messages: nil, failing: 0, answers: nil, picture: nil, picture_chat: nil,
                  selection: nil, hidden: [])
    helper = Class.new(MonadicApp) { include helper_module }.new
    allow(helper).to receive(:sleep)
    # Whether the message may search is the server's (the setting and the
    # app, WebSearchSetting); here the message's "websearch" stands for it.
    allow(Monadic::WebSearchSetting).to receive(:allowed?).and_return([true, "true"].include?(message["websearch"]))
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
    unless hidden.empty?
      table = Monadic::Utils::Privacy::Words.start!(session)
      hidden.each { |word| table.confirm!(word, "PERSON") }
    end
    @turn_picture = nil
    request_id = Monadic::Workspace::Ids.generate(:request)
    if picture
      @turn_picture = Monadic::Workbench::Picture.new(
        id: "p_#{"a" * 20}", chat_id: picture_chat || chat, request_id: request_id, item_id: PICTURED_ITEM,
        version: PICTURED_VERSION, page: 2, pages: 5,
        mark: { "shape" => "ellipse", "x" => 0.25, "y" => 0.5, "w" => 0.25, "h" => 0.125 }, bytes: picture
      )
    end
    pointed = {}
    pointed[:pictures] = [@turn_picture] if @turn_picture
    if selection
      pointed[:selection] = Monadic::Workbench::Selection.new(
        request_id: request_id, item_id: PICTURED_ITEM, version: PICTURED_VERSION, page: 2, pages: 5,
        text: Monadic::Workbench::Selection.text_of(selection), cut: false
      )
    end
    pointed[:request_id] = request_id unless pointed.empty?
    context = if answering
                Monadic::Workspace::RequestContext.new(chat_id: chat, parameters: answering,
                                                       settings: Monadic::TurnSettings.of(answering))
              else
                Monadic::Workspace::RequestContext.new(chat_id: chat, parameters: session[:parameters],
                                                       settings: Monadic::TurnSettings.accepted(message, kept),
                                                       **pointed)
              end
    Monadic::Workspace::RequestContext.with(context) { helper.api_request("user", session) { |_| } }
    bodies
  end
end
