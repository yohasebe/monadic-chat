# frozen_string_literal: true

require_relative "../../spec_helper"
require "tmpdir"
require "digest"
require "json"
require_relative "../../../lib/monadic/workspace/ids"
require_relative "../../../lib/monadic/workbench/channel"
require_relative "../../../lib/monadic/workbench/look"
require_relative "../../../lib/monadic/workbench/look/availability"
require_relative "../../../lib/monadic/workbench/look/record"
require_relative "../../../lib/monadic/shared_tools/workbench_tools"

RSpec.describe "looking at the work screen (look_at_workbench)" do
  let(:look) { Monadic::Workbench::Look }

  def png(width, height, salt = "")
    "\x89PNG\r\n\x1A\n".b + [13].pack("N") + "IHDR".b + [width, height].pack("NN") + "\x08\x02\x00\x00\x00".b +
      "\x00" * 4 + salt.b
  end

  around do |example|
    Dir.mktmpdir("workbench-look-spec") do |dir|
      @data = File.join(dir, "data")
      @state = File.join(dir, "state")
      FileUtils.mkdir_p([@data, @state])
      example.run
    end
  end

  let(:store) { Monadic::Workbench::Store.new(File.join(@state, "workbench")) }
  let(:chat) { Monadic::Workspace::Ids.generate(:chat) }
  let(:request_id) { Monadic::Workspace::Ids.generate(:request) }
  let(:session) { { chat_id: chat, messages: [] } }
  let(:live_tabs) { { "tab-1" => 1, "tab-2" => 1 } }

  before do
    Monadic::Workbench::Board.reset!
    Monadic::Workbench::Board.live = ->(t) { live_tabs[t] }
    Monadic::Workbench::Look::Ledger.reset!
    allow(Monadic::Workbench::Store).to receive(:default).and_return(store)
    allow(Monadic::Utils::Environment).to receive(:data_path).and_return(@data)
    allow(Monadic::Utils::Environment).to receive(:state_path).and_return(@state)
  end

  after { Monadic::Workspace::Ledger.clear_unsettled! }

  around do |example|
    transport = Monadic::Workbench::Capture.transport
    example.run
  ensure
    Monadic::Workbench::Capture.transport = transport
  end

  def write(path, bytes)
    full = File.join(@data, path)
    FileUtils.mkdir_p(File.dirname(full))
    File.binwrite(full, bytes)
    full
  end

  def board
    Monadic::Workbench::Board.for(chat, store: store)
  end

  def epoch
    Monadic::Workspace::Chats.epoch(chat)
  end

  def open_file(path, tab: "tab-1")
    board.add_file(path: path, origin: { actor: :user, source: :panel, tab: tab, generation: 1 }, epoch: epoch).first
  end

  def caller_for(tab: "tab-1", generation: 1, at: epoch, of: session)
    Monadic::Workbench::Caller.new(chat_id: chat, epoch: at, request_id: request_id, session: of, tab: tab,
                                   generation: generation)
  end

  def ledger
    Monadic::Workbench::Look::Ledger.find(chat, request_id)
  end

  describe "ImageValue" do
    it "is made only from bytes the server checked, and its text forms carry no bytes" do
      expect { look::ImageValue.new }.to raise_error(NoMethodError)
      value = look::ImageValue.checked(png(4, 3, "secret-bytes"), source: "workbench_file")
      expect(value).to be_frozen
      expect([value.width, value.height, value.content_type]).to eq([4, 3, "image/png"])
      expect(value.sha256).to eq(Digest::SHA256.hexdigest(png(4, 3, "secret-bytes")))
      [value.to_s, value.inspect, JSON.generate([value])].each do |text|
        expect(text).not_to include(value.base64)
        expect(text).not_to include("secret-bytes")
      end
    end

    it "refuses what is not an image, and an image too large to send" do
      expect { look::ImageValue.checked("not an image", source: "workbench_file") }
        .to raise_error(look::Refused) { |e| expect(e.reason).to eq("unsupported_kind") }
      big = png(100, 100, "x" * (4 * 1024 * 1024))
      expect { look::ImageValue.checked(big, source: "workbench_file") }
        .to raise_error(look::Refused) { |e| expect(e.reason).to eq("too_large") }
    end
  end

  describe "a look" do
    it "reads the image file the tab has selected, at its version, and keeps it for the request" do
      write("pics/cat.png", png(8, 6))
      item = open_file("pics/cat.png")
      result = look.run(caller_for, scope: "visible")
      expect(result).to be_a(look::Result)
      body = JSON.parse(result.to_s)
      expect(body).to include("status" => "looked", "scope" => "visible", "observation_id" => result.observation_id)
      expect(body["item"]).to include("kind" => "image", "name" => "cat.png", "path" => "pics/cat.png",
                                      "version" => item["file"]["sha256"][0, 12])
      expect(result.to_s).not_to include(Base64.strict_encode64(png(8, 6)))
      ledger.bind(result.observation_id, "call_1")
      seen = ledger.images_for(["call_1"])
      expect(seen.map(&:id)).to eq([result.observation_id])
      expect(seen.first.image.bytes).to eq(png(8, 6))
    end

    it "gives a text file whole as text, with its lines" do
      write("notes.txt", "﻿one\r\ntwo\nthree\n")
      open_file("notes.txt")
      body = JSON.parse(look.run(caller_for, scope: "whole").to_s)
      expect(body["text"]).to eq("one\ntwo\nthree\n")
      expect(body["lines"]).to eq("first" => 1, "last" => 3, "total" => 3, "last_line_cut" => false)
      expect(body["truncated"]).to be(false)
      expect(ledger.records.first).to include("kind" => "text", "scope" => "whole", "image" => false,
                                              "lines" => { "first" => 1, "last" => 3, "total" => 3 })
    end

    it "says the text of a file the work screen can draw is its source, not the drawing" do
      write("notes.md", "# Title\n")
      open_file("notes.md")
      body = JSON.parse(look.run(caller_for, scope: "whole").to_s)
      expect(body["text"]).to eq("# Title\n")
      expect(body["source_text"]).to match(/source text .* not what the drawing looks like/)
      write("plain.txt", "x\n")
      open_file("plain.txt")
      expect(JSON.parse(look.run(caller_for, scope: "whole").to_s)).not_to have_key("source_text")
    end

    it "cuts long text and says so, without a total" do
      write("long.txt", "line\n" * 20_000)
      open_file("long.txt")
      body = JSON.parse(look.run(caller_for, scope: "whole").to_s)
      expect(body["text"].length).to be <= look::TEXT_CHARS
      expect(body["text"]).to end_with("\n")
      expect(body["truncated"]).to be(true)
      expect(body["lines"]["total"]).to be_nil
    end

    it "says when the last line given is only its beginning, and when the file holds no line" do
      write("one-line.txt", "x" * (look::TEXT_CHARS + 10))
      open_file("one-line.txt")
      body = JSON.parse(look.run(caller_for, scope: "whole").to_s)
      expect(body["lines"]).to include("last" => 1, "last_line_cut" => true)
      expect(ledger.records.last["lines"]).to include("partial" => true)
      write("empty.txt", "")
      open_file("empty.txt")
      body = JSON.parse(look.run(caller_for, scope: "whole").to_s)
      expect(body).to include("empty" => true, "truncated" => false)
      expect(ledger.records.last).to include("empty" => true)
    end

    it "records the whole version, the image's own hash, where it came from and the item" do
      write("a.png", png(2, 2))
      item = open_file("a.png")
      look.run(caller_for)
      expect(ledger.records.first).to include("version" => item["file"]["sha256"], "item_id" => item["id"],
                                              "image_sha256" => Digest::SHA256.hexdigest(png(2, 2)),
                                              "source" => "workbench_file")
      expect(Monadic::Workbench::Look::Record.clean(ledger.records).first).to include("image_sha256", "source", "item_id")
    end

    it "does not widen the visible lines of a text file to the whole file when the page does not say them" do
      write("notes.txt", "one\n")
      open_file("notes.txt")
      Monadic::Workbench::Capture.transport = lambda do |_tab, _generation, _chat, json|
        id = JSON.parse(json)["id"]
        Thread.new { Monadic::Workbench::Capture.reading(id, 2) { { "range" => nil, "note" => "unknown" } } }
        true
      end
      expect(look.run(caller_for, scope: "visible")).to start_with("❌").and include("(range_unknown)")
      expect(ledger).to be_nil.or(satisfy { |l| l.records.empty? })
    end

    it "refuses what the tab has not selected, another tab's selection, and an old connection" do
      write("a.png", png(2, 2))
      open_file("a.png", tab: "tab-2")
      expect(look.run(caller_for(tab: "tab-1"))).to include("(no_selection)")
      live_tabs["tab-2"] = 2
      expect(look.run(caller_for(tab: "tab-2", generation: 1))).to include("(connection_gone)")
    end

    it "does not take another version, the latest image or another item when the file changed or is gone" do
      write("a.png", png(2, 2))
      open_file("a.png")
      write("a.png", png(2, 2, "changed"))
      expect(look.run(caller_for)).to include("(changed)")
      File.delete(File.join(@data, "a.png"))
      expect(look.run(caller_for)).to include("(missing)")
      expect(ledger).to be_nil.or(satisfy { |l| l.records.empty? })
    end

    it "gives nothing when the selection changes while the file is read" do
      write("a.png", png(2, 2))
      write("b.png", png(3, 3))
      first = open_file("a.png")
      second = open_file("b.png")
      board.select(tab: "tab-1", generation: 1, item_id: first["id"])
      allow(Monadic::Workbench::FileItem).to receive(:read).and_wrap_original do |original, entry|
        board.select(tab: "tab-1", generation: 1, item_id: second["id"])
        original.call(entry)
      end
      expect(look.run(caller_for)).to include("(selection_changed)")
    end

    it "sends nothing from a Private chat, and nothing after a Reset" do
      write("a.png", png(2, 2))
      open_file("a.png")
      expect(look.run(caller_for(of: session.merge(Monadic::History::Policy::SESSION_KEY => Monadic::History::Policy::PRIVATE))))
        .to include("(private)")
      stale = caller_for
      Monadic::Workspace::Chats::EPOCHS_LOCK.synchronize { Monadic::Workspace::Chats::EPOCHS[chat] += 1 }
      expect(look.run(stale)).to include("(cancelled)")
    end

    it "looks for a session that is not a Hash, as the server's is" do
      write("a.png", png(2, 2))
      open_file("a.png")
      rack_like = Class.new do
        def initialize(data) = (@data = data)
        def [](key) = @data[key.to_sym]
        def []=(key, value)
          @data[key.to_sym] = value
        end

        def key?(key) = @data.key?(key.to_sym)
      end.new(session)
      expect(look.run(caller_for(of: rack_like))).to be_a(look::Result)
    end

    it "refuses a scope it does not know, and a reply without a caller" do
      expect(look.run(caller_for, scope: "all")).to include("(unsupported_kind)")
      expect(look.run(nil)).to include("(connection_gone)")
    end
  end

  describe "through the chat's Privacy Filter" do
    # A pipeline that masks e-mail addresses wherever they are, as the
    # filter's own detection does, with no word marked by the user.
    def masking_pipeline
      Class.new do
        def before_send_to_llm(message) = Struct.new(:text).new(message.text.gsub(/\w+@example\.com/, "<<EMAIL_1>>"))
        def registry_state = { terms: [] }
      end.new
    end

    it "masks what a look gives as text, with no word marked" do
      write("mail.txt", "write to alice@example.com\n")
      open_file("mail.txt")
      allow(Monadic::Utils::Privacy::Outbound).to receive(:pipeline!).and_return(masking_pipeline)
      result = look.run(caller_for, scope: "whole")
      expect(result.to_s).to include("<<EMAIL_1>>")
      expect(result.to_s).not_to include("alice@example.com")
    end

    it "masks the caption of an image" do
      write("alice@example.com.png", png(2, 2))
      open_file("alice@example.com.png")
      allow(Monadic::Utils::Privacy::Outbound).to receive(:pipeline!).and_return(masking_pipeline)
      look.run(caller_for)
      looked = ledger.observations_with_content.first
      expect([looked.caption, looked.result].join).not_to include("alice@example.com")
    end

    it "gives nothing when a marked word would be left, or when the filter cannot check it" do
      write("notes.txt", "the secret plan\n")
      open_file("notes.txt")
      # A chat with marked words is Private and is refused before this; the
      # check stands behind that.
      allow(Monadic::Utils::Privacy::Outbound).to receive(:pipeline!).and_return(nil)
      allow(Monadic::Utils::Privacy::Outbound).to receive(:terms_of).and_return(["secret plan"])
      expect(look.run(caller_for, scope: "whole")).to include("(filtered)")
      allow(Monadic::Utils::Privacy::Outbound).to receive(:pipeline!)
        .and_raise(Monadic::Utils::Privacy::Outbound::Refused, "masking is not available")
      expect(look.run(caller_for, scope: "whole")).to include("(filtered)")
      expect(ledger).to be_nil.or(satisfy { |l| l.records.empty? })
    end

    it "does not look at all in a chat with marked words (such a chat is Private)" do
      write("notes.txt", "the secret plan\n")
      open_file("notes.txt")
      marked = session.merge(monadic_state: { privacy: { terms: [{ text: "secret plan" }] } })
      expect(look.run(caller_for(of: marked), scope: "whole")).to include("(private)")
    end

    it "does not look at all in a chat with the filter on (such a chat is Private)" do
      write("notes.txt", "x\n")
      open_file("notes.txt")
      filtered = session.merge(_privacy_session_enabled: true, _privacy_pipeline: masking_pipeline)
      expect(look.run(caller_for(of: filtered), scope: "whole")).to include("(private)")
    end
  end

  describe "the ledger of a request" do
    it "keeps each look as its own observation, in order, and lets them go when the reply ends" do
      write("a.png", png(2, 2))
      open_file("a.png")
      first = look.run(caller_for)
      second = look.run(caller_for)
      expect(first.observation_id).not_to eq(second.observation_id)
      ledger.bind(first.observation_id, "call_1")
      ledger.bind(second.observation_id, "call_2")
      expect(ledger.images_for(%w[call_2 call_1]).map(&:id)).to eq([first.observation_id, second.observation_id])
      expect(Monadic::Workbench::Look::Ledger.take(request_id)).not_to be_nil
      expect(ledger).to be_nil
    end

    it "refuses a new reply's look when the ledgers are full, and lets none in use go" do
      write("a.png", png(2, 2))
      open_file("a.png")
      first = look.run(caller_for).observation_id
      stub_const("Monadic::Workbench::Look::Ledger::LEDGERS", 2)
      Monadic::Workbench::Look::Ledger.for(chat, epoch, Monadic::Workspace::Ids.generate(:request))
      other = Monadic::Workbench::Caller.new(chat_id: chat, epoch: epoch, request_id: Monadic::Workspace::Ids.generate(:request),
                                             session: session, tab: "tab-1", generation: 1)
      expect(look.run(other)).to include("(busy)")
      expect(ledger.records.map { |r| r["id"] }).to eq([first])
    end

    it "refuses an image past what all replies may hold" do
      write("a.png", png(2, 2))
      open_file("a.png")
      stub_const("Monadic::Workbench::Look::Ledger::ALL_IMAGE_BYTES", png(2, 2).bytesize)
      look.run(caller_for)
      expect(look.run(caller_for)).to include("(busy)")
    end

    it "lets only one of two looks at once take the last room for an image" do
      image = look::ImageValue.checked(png(2, 2), source: "workbench_file")
      stub_const("Monadic::Workbench::Look::Ledger::ALL_IMAGE_BYTES", image.bytes.bytesize)
      ledgers = Array.new(2) do
        Monadic::Workbench::Look::Ledger.for(chat, epoch, Monadic::Workspace::Ids.generate(:request))
      end
      gate = Queue.new
      allow(Monadic::Workbench::Look::Ledger).to receive(:reserve).and_wrap_original do |original, bytes|
        gate.pop
        original.call(bytes)
      end
      results = ledgers.map do |ledger|
        Thread.new do
          ledger.add(item_id: "i", kind: "image", name: "a.png", path: "a.png", version: "a" * 64, image: image)
          :kept
        rescue look::Refused => e
          e.reason
        end
      end
      2.times { gate << true }
      expect(results.map(&:value).sort_by(&:to_s)).to eq([:kept, "busy"].sort_by(&:to_s))
    end

    it "closes a ledger open too long instead of dropping it: its record stays, its images go, a request holding it is not sent" do
      write("a.png", png(2, 2))
      open_file("a.png")
      id = look.run(caller_for).observation_id
      held = ledger
      stub_const("Monadic::Workbench::Look::Ledger::KEEP_FOR", -1)
      Monadic::Workbench::Look::Ledger.for(chat, epoch, Monadic::Workspace::Ids.generate(:request))
      expect(held).to be_closed
      expect(held.observations_with_content).to be_empty
      expect(Monadic::Workbench::Look::Ledger.of_request(chat, request_id)).to equal(held)
      attempt = Monadic::Workbench::Look::Attempt.new(held, [id])
      expect(attempt.refusal(session, provider: "openai", model: "m")).to include("let go")
    end

    it "closes a ledger open past the time its records are kept, and drops only a closed one" do
      write("a.png", png(2, 2))
      open_file("a.png")
      look.run(caller_for)
      held = ledger
      stub_const("Monadic::Workbench::Look::Ledger::KEEP_FOR", -1)
      stub_const("Monadic::Workbench::Look::Ledger::DROP_AFTER", -1)
      Monadic::Workbench::Look::Ledger.for(chat, epoch, Monadic::Workspace::Ids.generate(:request))
      expect(held).to be_closed
      expect(Monadic::Workbench::Look::Ledger.reserve(Monadic::Workbench::Look::Ledger::ALL_IMAGE_BYTES)).to be(true)
      Monadic::Workbench::Look::Ledger.for(chat, epoch, Monadic::Workspace::Ids.generate(:request))
      expect(Monadic::Workbench::Look::Ledger.of_request(chat, request_id)).to be_nil
    end

    it "gives back an image's room once when the look is stopped after reserving it" do
      image = look::ImageValue.checked(png(2, 2), source: "workbench_file")
      held = Monadic::Workbench::Look::Ledger.for(chat, epoch, request_id)
      reserved = Queue.new
      go_on = Queue.new
      allow(held).to receive(:add_reserved).and_wrap_original do |original, *args|
        reserved << true
        go_on.pop
        original.call(*args)
      end
      thread = Thread.new do
        held.add(item_id: "i", kind: "image", name: "a.png", path: "a.png", version: "a" * 64, image: image)
      end
      reserved.pop(timeout: 5)
      thread.kill
      go_on << true
      thread.join(5)
      held.close!
      everything = Monadic::Workbench::Look::Ledger::ALL_IMAGE_BYTES
      expect(Monadic::Workbench::Look::Ledger.reserve(everything)).to be(true)
      expect(Monadic::Workbench::Look::Ledger.reserve(1)).to be(false)
    end

    context "when the thread is stopped (Cancel)" do
      let(:image) { look::ImageValue.checked(png(2, 2), source: "workbench_file") }
      let(:everything) { Monadic::Workbench::Look::Ledger::ALL_IMAGE_BYTES }

      def holding_image(request = Monadic::Workspace::Ids.generate(:request))
        ledger = Monadic::Workbench::Look::Ledger.for(chat, epoch, request)
        ledger.add(item_id: "i", kind: "image", name: "a.png", path: "a.png", version: "a" * 64, image: image)
        ledger
      end

      # The room all ledgers have left is everything but other's image.
      def expect_only(other)
        expect(other.observations_with_content.size).to eq(1)
        expect(Monadic::Workbench::Look::Ledger.reserve(everything - image.bytes.bytesize)).to be(true)
        expect(Monadic::Workbench::Look::Ledger.reserve(1)).to be(false)
      end

      it "gives back an image's room once when stopped right after it was kept" do
        held = Monadic::Workbench::Look::Ledger.for(chat, epoch, request_id)
        other = holding_image
        kept = Queue.new
        go_on = Queue.new
        allow(held).to receive(:add_reserved).and_wrap_original do |original, *args|
          id = original.call(*args)
          kept << true
          go_on.pop
          id
        end
        thread = Thread.new do
          held.add(item_id: "i", kind: "image", name: "a.png", path: "a.png", version: "a" * 64, image: image)
        end
        expect(kept.pop(timeout: 5)).to be(true)
        thread.kill
        go_on << true
        thread.join(5)
        expect(thread).not_to be_alive
        held.close!
        expect_only(other)
      end

      it "gives back the room of a ledger closed as it expires, once" do
        expired = holding_image(request_id)
        other = holding_image
        allow(expired).to receive(:made_at).and_return(-Monadic::Workbench::Look::Ledger::DROP_AFTER * 2.0)
        releasing = Queue.new
        go_on = Queue.new
        allow(Monadic::Workbench::Look::Ledger).to receive(:release).and_wrap_original do |original, bytes|
          releasing << true
          go_on.pop
          original.call(bytes)
        end
        thread = Thread.new { Monadic::Workbench::Look::Ledger.for(chat, epoch, Monadic::Workspace::Ids.generate(:request)) }
        expect(releasing.pop(timeout: 5)).to be(true)
        thread.kill
        go_on << true
        thread.join(5)
        expect(thread).not_to be_alive
        expect(expired).to be_closed
        allow(Monadic::Workbench::Look::Ledger).to receive(:release).and_call_original
        expired.close!
        expect_only(other)
      end

      it "closes a ledger it takes" do
        taken = holding_image(request_id)
        other = holding_image
        closing = Queue.new
        go_on = Queue.new
        allow(taken).to receive(:close!).and_wrap_original do |original|
          closing << true
          go_on.pop
          original.call
        end
        thread = Thread.new { Monadic::Workbench::Look::Ledger.take(request_id) }
        expect(closing.pop(timeout: 5)).to be(true)
        thread.kill
        go_on << true
        thread.join(5)
        expect(thread).not_to be_alive
        expect(taken).to be_closed
        expect_only(other)
      end
    end

    it "lets the images and texts go when the reply ends, and what was never posted is unsent" do
      write("a.png", png(2, 2))
      open_file("a.png")
      id = look.run(caller_for).observation_id
      ledger.prepare([id])
      taken = Monadic::Workbench::Look::Ledger.take(request_id)
      expect(taken.records.first["state"]).to eq("unsent")
      expect(taken.observations_with_content).to be_empty
    end

    it "refuses a look past the request's limit and keeps what it has" do
      write("a.png", png(2, 2))
      open_file("a.png")
      results = Array.new(Monadic::Workbench::Look::Ledger::OBSERVATIONS + 1) { look.run(caller_for) }
      expect(results.last).to include("(too_large)")
      expect(ledger.records.size).to eq(Monadic::Workbench::Look::Ledger::OBSERVATIONS)
    end

    it "keeps sent once sent, and unknown unless sent later" do
      l = Monadic::Workbench::Look::Ledger.for(chat, epoch, request_id)
      write("a.png", png(2, 2))
      open_file("a.png")
      id = look.run(caller_for).observation_id
      l.mark([id], "embedded")
      l.mark([id], "unknown")
      l.mark([id], "unsent")
      expect(l.records.first["state"]).to eq("unknown")
      l.mark([id], "sent")
      l.mark([id], "refused")
      expect(l.records.first["state"]).to eq("sent")
    end

    it "keeps no bytes and no text in what the message records" do
      write("notes.txt", "private words\n")
      open_file("notes.txt")
      look.run(caller_for, scope: "whole")
      expect(JSON.generate(ledger.records)).not_to include("private words")
    end
  end

  describe "Availability" do
    let(:availability) { Monadic::Workbench::Look::Availability }
    let(:openai_tools) do
      [{ "type" => "function", "function" => { "name" => "show_on_workbench" } },
       { "type" => "function", "function" => { "name" => "look_at_workbench" } }]
    end

    before do
      allow(Monadic::Utils::ModelSpec).to receive(:tool_capability?).and_return(true)
      allow(Monadic::Utils::ModelSpec).to receive(:get_model_property).and_call_original
    end

    def vision(value)
      allow(Monadic::Utils::ModelSpec).to receive(:get_model_property).with("m", "vision_capability").and_return(value)
    end

    it "offers the look to a model known to take images, through a helper that carries its image" do
      vision(true)
      expect(availability.filter(openai_tools, session: session, provider: "openai", model: "m")).to eq(openai_tools)
    end

    it "leaves it out for a model whose image input is unknown or absent, and for other helpers" do
      [nil, false].each do |value|
        vision(value)
        names = availability.filter(openai_tools, session: session, provider: "openai", model: "m")
                            .map { |t| t.dig("function", "name") }
        expect(names).to eq(["show_on_workbench"])
      end
      vision(true)
      expect(availability.offered?(session: session, provider: "elsewhere", model: "m")).to be(false)
    end

    it "leaves it out in a Private chat and for a model without tools" do
      vision(true)
      private_session = session.merge(Monadic::History::Policy::SESSION_KEY => Monadic::History::Policy::PRIVATE)
      expect(availability.offered?(session: private_session, provider: "openai", model: "m")).to be(false)
      allow(Monadic::Utils::ModelSpec).to receive(:tool_capability?).and_return(false)
      expect(availability.offered?(session: session, provider: "openai", model: "m")).to be(false)
    end

    it "takes the tool out of every provider's shape" do
      shapes = [
        [{ "name" => "look_at_workbench" }, { "name" => "x" }],
        [{ "type" => "function", "name" => "look_at_workbench" }, { "type" => "function", "name" => "x" }],
        [{ "function_declarations" => [{ "name" => "look_at_workbench" }, { "name" => "x" }] }],
        [{ "function_declarations" => [{ "name" => "look_at_workbench" }] }, { "google_search" => {} }]
      ]
      vision(false)
      out = shapes.map { |tools| availability.filter(tools, session: session, provider: "openai", model: "m") }
      expect(JSON.generate(out)).not_to include("look_at_workbench")
      expect(out[2]).to eq([{ "function_declarations" => [{ "name" => "x" }] }])
      expect(out[3]).to eq([{ "google_search" => {} }])
    end
  end

  describe "Record" do
    it "keeps the listed fields of a well formed record only" do
      kept = Monadic::Workbench::Look::Record.clean(
        [{ "id" => "look_1", "kind" => "image", "state" => "sent", "name" => "a\nb.png", "bytes" => "AAAA",
           "image" => true, "lines" => { "first" => 1, "x" => 2 } },
         { "id" => "look_2", "kind" => "audio", "state" => "sent" },
         { "id" => "look_3", "kind" => "pdf", "state" => "sent", "image" => true, "source" => "workbench_capture",
           "pages" => { "first" => 2, "last" => 2, "total" => 9, "x" => 1 },
           "parts" => { "image" => true, "page_text" => "pdf_text_unavailable", "selection" => "words", "other" => true } },
         "junk"]
      )
      expect(kept).to eq([{ "id" => "look_1", "kind" => "image", "state" => "sent", "name" => "a b.png", "image" => true,
                            "lines" => { "first" => 1 } },
                          { "id" => "look_3", "kind" => "pdf", "state" => "sent", "image" => true, "source" => "workbench_capture",
                            "pages" => { "first" => 2, "last" => 2, "total" => 9 },
                            "parts" => { "image" => true, "page_text" => "pdf_text_unavailable" } }])
      expect(Monadic::Workbench::Look::Record.clean("x")).to be_nil
    end
  end
end
