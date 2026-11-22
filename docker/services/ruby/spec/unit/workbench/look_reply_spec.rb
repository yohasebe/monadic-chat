# frozen_string_literal: true

require "spec_helper"
require "json"
require "tmpdir"
require_relative "../../../lib/monadic/utils/websocket"
require_relative "../../../lib/monadic/workspace"
require_relative "../../../lib/monadic/workbench/look"

# What a reply looked at in the work screen is said on the chat: on the
# reply's message when it is recorded, on the user's message when the reply
# ends without one, also when it ends in the thread that ran it (which has
# no connection's session). Either way the record names what was looked at
# and how far it went, with no bytes, and the request's looks are let go.
RSpec.describe "the looks of a reply, when it ends" do
  let(:host) { Class.new { include WebSocketHelper }.new }
  let(:broadcasts) { Queue.new }
  let(:chat) { Monadic::Workspace::Ids.generate(:chat) }
  let(:request_id) { Monadic::Workspace::Ids.generate(:request) }
  let(:session) do
    { chat_id: chat, parameters: {},
      messages: [{ "role" => "user", "mid" => "u1", "text" => "look", "request_id" => request_id }] }
  end

  def png
    "\x89PNG\r\n\x1A\n".b + [13].pack("N") + "IHDR".b + [2, 2].pack("NN") + "\x08\x02\x00\x00\x00".b + "\x00" * 4
  end

  def looked(of: session, at_chat: chat)
    ledger = Monadic::Workbench::Look::Ledger.for(at_chat, Monadic::Workspace::Chats.epoch(at_chat), request_id,
                                                   session: of, tab: "tab-1")
    image = Monadic::Workbench::Look::ImageValue.checked(png, source: "workbench_file")
    id = ledger.add(item_id: "i_1", kind: "image", name: "shot.png", path: "shot.png", version: "a" * 64,
                    scope: "visible", image: image)
    ledger.mark([id], "unknown")
    ledger
  end

  # As the thread that runs a reply ends it: no connection's session there.
  def end_in_reply_thread(outcome)
    Thread.new do
      Thread.current[:rack_session] = nil
      host.send(:finish_reply, request_id, outcome, "tab-1")
    end.join
  end

  def sent
    list = []
    list << broadcasts.pop until broadcasts.empty?
    list
  end

  let(:saved) { Queue.new }
  let(:accepted) { true }

  before do
    Monadic::Workbench::Look::Ledger.reset!
    allow(host).to receive(:send_or_broadcast) { |msg, *_| broadcasts << JSON.parse(msg) }
    # The tab's copy of the chat, and the history: what each would keep.
    allow(WebSocketHelper).to receive(:update_session_state) { accepted }
    allow(Monadic::History).to receive(:record) do |kept, tab:|
      saved << [tab, kept[:messages].first["workbench_looks"]]
    end
  end

  it "keeps them on the user's message when the reply ends without its own, in the reply's thread, and tells the page" do
    looked
    end_in_reply_thread("no_reply")
    turn = session[:messages].first
    expect(turn["workbench_looks"]).to match([a_hash_including("name" => "shot.png", "state" => "unknown", "image" => true)])
    expect(JSON.generate(turn)).not_to include(Base64.strict_encode64(png))
    event = sent.find { |b| b["type"] == "workbench_looks" }
    expect(event).to include("mid" => "u1", "looks" => turn["workbench_looks"])
    expect(Monadic::Workbench::Look::Ledger.of_request(chat, request_id)).to be_nil
  end

  it "saves the chat with them from the reply's thread, for the tab the request came from" do
    looked
    end_in_reply_thread("no_reply")
    tab, looks = saved.pop(timeout: 1)
    expect(tab).to eq("tab-1")
    expect(looks).to match([a_hash_including("name" => "shot.png")])
    expect(Thread.current[:rack_session]).to be_nil
  end

  context "when a newer connection has the tab" do
    let(:accepted) { false }

    it "keeps them on the message but does not write the history from the older one" do
      looked
      end_in_reply_thread("no_reply")
      expect(session[:messages].first["workbench_looks"]).not_to be_nil
      expect(saved).to be_empty
    end
  end

  it "says nothing on a chat the session has left" do
    looked
    session[:chat_id] = Monadic::Workspace::Ids.generate(:chat)
    end_in_reply_thread("no_reply")
    expect(session[:messages].first).not_to have_key("workbench_looks")
    expect(sent.map { |b| b["type"] }).not_to include("workbench_looks")
  end

  it "gives the reply's message the records when it is recorded, once" do
    looked
    expect(host.send(:workbench_looks_of_reply, session, request_id))
      .to match([a_hash_including("name" => "shot.png", "state" => "unknown")])
    expect(host.send(:workbench_looks_of_reply, session, request_id)).to be_nil
    end_in_reply_thread("done")
    expect(session[:messages].first).not_to have_key("workbench_looks")
  end
end
