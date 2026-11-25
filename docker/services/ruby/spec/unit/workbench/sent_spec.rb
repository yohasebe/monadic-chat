# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "digest"
require_relative "../../../lib/monadic/adapters/base_vendor_helper"
require_relative "../../../lib/monadic/workspace"
require_relative "../../../lib/monadic/workbench/look"
require_relative "../../../lib/monadic/workbench/sent"
require_relative "../../../lib/monadic/workbench/retention"

# The images of the work screen that left for a provider, kept in the
# chat's folder for its export: once each, taken only as kept, removed when
# no message names them.
RSpec.describe Monadic::Workbench::Sent do
  def png(salt = "")
    "\x89PNG\r\n\x1A\n".b + [13].pack("N") + "IHDR".b + [2, 2].pack("NN") + "\x08\x02\x00\x00\x00".b + "\x00".b * 4 + salt.b
  end

  around do |example|
    Dir.mktmpdir("sent-spec") do |dir|
      @data = File.join(dir, "data")
      @state = File.join(dir, "state")
      FileUtils.mkdir_p([@data, @state])
      @data = File.realpath(@data)
      example.run
    end
  end

  let(:chat) { Monadic::Workspace::Ids.generate(:chat) }

  before do
    allow(Monadic::Utils::Environment).to receive(:data_path).and_return(@data)
    allow(Monadic::Utils::Environment).to receive(:state_path).and_return(@state)
  end

  after { described_class::PENDING_LOCK.synchronize { described_class::PENDING.clear } }

  def keep(bytes) = described_class.keep!(chat, bytes, "image/png", app_name: "ChatOpenAI")
  def dir = described_class.dir_for(chat)
  def files = Dir.children(dir).sort
  def sent_look(sha) = { "role" => "assistant", "workbench_looks" => [{ "image_sha256" => sha, "state" => "sent" }] }

  describe "keeping" do
    it "keeps an image once in the chat's folder, named by its sha256, however often it went" do
      sha = keep(png("a"))
      keep(png("a"))
      expect(sha).to eq(Digest::SHA256.hexdigest(png("a")))
      expect(dir).to end_with("/sent")
      expect(dir).to include("/conversations/")
      expect(files).to eq(["#{sha}.png"])
      expect(described_class.read(chat, sha)).to eq(png("a"))
    end

    it "reads as gone an image the user changed, and does not write over it" do
      sha = keep(png("a"))
      File.binwrite(File.join(dir, "#{sha}.png"), png("changed"))
      expect(described_class.read(chat, sha)).to be_nil
      expect { keep(png("a")) }.to raise_error(described_class::Unavailable)
      expect(File.binread(File.join(dir, "#{sha}.png"))).to eq(png("changed"))
    end

    it "keeps no more than the chat may, and nothing for a chat without a folder" do
      stub_const("#{described_class}::LIMIT_BYTES", png("a").bytesize + 10)
      keep(png("a"))
      expect { keep(png("bb")) }.to raise_error(described_class::Full)
      other = Monadic::Workspace::Ids.generate(:chat)
      expect { described_class.keep!(other, png, "image/png") }.to raise_error(described_class::Unavailable)
    end
  end

  describe "nearing what the chat may keep" do
    it "tells once, as the images it keeps pass the mark, how much it keeps" do
      size = png("a").bytesize
      stub_const("#{described_class}::LIMIT_BYTES", size * 10)
      stub_const("#{described_class}::WARN_BYTES", (size * 2) + 1)
      keep(png("a"))
      keep(png("b"))
      expect(described_class.take_crossing(chat)).to be_nil
      keep(png("c"))
      expect(described_class.take_crossing(chat)).to eq(size * 3)
      expect(described_class.take_crossing(chat)).to be_nil
      keep(png("d"))
      expect(described_class.take_crossing(chat)).to be_nil
    end

    it "estimates what the images the messages name take, and whether an export of them is near its limit" do
      sha = keep(png("a"))
      keep(png("unnamed"))
      expect(described_class.estimate(chat, [sent_look(sha)])).to eq(bytes: png("a").bytesize, near: false)
      stub_const("#{described_class}::EXPORT_LIMIT", 10)
      expect(described_class.estimate(chat, [sent_look(sha)])[:near]).to be(true)
      expect(described_class.estimate(nil, [sent_look(sha)])).to eq(bytes: 0, near: false)
    end
  end

  describe "releasing" do
    it "removes the images no message names, but none a running reply sent, nor one the user changed" do
      named = keep(png("named"))
      unnamed = keep(png("unnamed"))
      running = keep(png("running"))
      changed = keep(png("changed"))
      described_class.done(chat, [named, unnamed, changed])
      File.binwrite(File.join(dir, "#{changed}.png"), png("other"))
      expect(described_class.release(chat, [sent_look(named)])).to eq(1)
      expect(files).to eq(["#{changed}.png", "#{named}.png", "#{running}.png"].sort)
      described_class.done(chat, [running])
      described_class.release(chat, [sent_look(named)])
      expect(files).to eq(["#{changed}.png", "#{named}.png"].sort)
    end

    it "removes every image it kept when the chat is discarded" do
      sha = keep(png("a"))
      described_class.done(chat, [sha])
      Monadic::Workbench::Retention.discard(chat)
      expect(files).to be_empty
    end

    it "names an image a look sent, was refused or may have sent, not one that never left" do
      looks = %w[sent refused unknown unsent embedded].map.with_index do |state, i|
        { "image_sha256" => i.to_s * 64, "state" => state }
      end
      expect(described_class.named_by([{ "workbench_looks" => looks }])).to eq(%w[0 1 2].map { |d| d * 64 })
    end
  end

  describe "a PDF a look gave as it is" do
    let(:pdf) { "%PDF-1.4\n1 0 obj\n<<>>\nendobj\n%%EOF\n".b }

    it "is kept, named by the look, exported and imported as a PDF, and released as an image is" do
      sha = described_class.keep!(chat, pdf, "application/pdf", app_name: "ChatClaude")
      expect(File.exist?(File.join(dir, "#{sha}.pdf"))).to be(true)
      described_class.done(chat, [sha])
      messages = [{ "role" => "assistant", "workbench_looks" => [{ "file_sha256" => sha, "state" => "sent" }] }]
      expect(described_class.named_by(messages)).to eq([sha])
      expect(described_class.release(chat, messages)).to eq(0)
      table, missing = described_class.export_table(chat, messages)
      expect(missing).to be_empty
      expect(table[sha]["content_type"]).to eq("application/pdf")
      expect(described_class.import_table(table, messages)).to eq(sha => { bytes: pdf, content_type: "application/pdf" })
      expect(described_class.release(chat, [])).to eq(1)
      expect { described_class.import_table({ sha => table[sha].merge("content_type" => "image/png") }, messages) }
        .to raise_error(described_class::BadFile)
    end
  end

  describe "an Office document a look gave as it is" do
    let(:docx) { "application/vnd.openxmlformats-officedocument.wordprocessingml.document" }
    let(:bytes) { "PK\x03\x04 a report".b }

    it "is kept under its kind's extension, exported as its type, and imported only as the type it says" do
      sha = described_class.keep!(chat, bytes, docx, app_name: "ChatOpenAI")
      expect(File.exist?(File.join(dir, "#{sha}.docx"))).to be(true)
      described_class.done(chat, [sha])
      messages = [{ "role" => "assistant", "workbench_looks" => [{ "file_sha256" => sha, "state" => "sent" }] }]
      table, = described_class.export_table(chat, messages)
      expect(table[sha]["content_type"]).to eq(docx)
      expect(described_class.import_table(table, messages)).to eq(sha => { bytes: bytes, content_type: docx })
      plain = Digest::SHA256.hexdigest("plain text")
      not_zip = { plain => { "content_type" => docx, "data" => Base64.strict_encode64("plain text") } }
      expect { described_class.import_table(not_zip, [{ "workbench_looks" => [{ "file_sha256" => plain, "state" => "sent" }] }]) }
        .to raise_error(described_class::BadFile)
    end
  end

  describe "a post of the picture of the work screen a message went with" do
    let(:helper) { Class.new { include BaseVendorHelper }.new }
    let(:request_id) { Monadic::Workspace::Ids.generate(:request) }
    let(:picture) do
      Monadic::Workbench::Picture.new(id: "p_#{'c' * 20}", chat_id: chat, request_id: request_id, item_id: "i_1",
                                      version: "v" * 64, page: nil, pages: nil, mark: { "shape" => "rect", "x" => 0.1, "y" => 0.1, "w" => 0.2, "h" => 0.2 },
                                      bytes: png("picture"), kind: "image")
    end
    let(:message) { { "role" => "user", "text" => "here", "request_id" => request_id, "workbench_picture" => picture.reference } }
    let(:session) do
      { Monadic::Workspace::Chats::SESSION_KEY => chat, parameters: { "app_name" => "ChatOpenAI" }, messages: [message] }
    end
    let(:ok) { double(status: HTTP::Response::Status.new(200)) }

    around do |example|
      Monadic::Workbench::Look::Ledger.reset!
      context = Monadic::Workspace::RequestContext.new(chat_id: chat, request_id: request_id, picture: picture)
      Monadic::Workspace::RequestContext.with(context) { example.run }
    end

    def post(&block) = helper.post_with_workbench_looks(session, provider: "openai", model: "m", &block)

    it "keeps it once as the first post of its turn goes, and names it on the message" do
      post { ok }
      sha = Digest::SHA256.hexdigest(png("picture"))
      expect(message["workbench_picture"]["sha256"]).to eq(sha)
      expect(Monadic::Workbench::Picture.clean(message["workbench_picture"])["sha256"]).to eq(sha)
      expect(described_class.named_by([message])).to eq([sha])
      expect(files).to eq(["#{sha}.png"])
      expect(described_class::PENDING).not_to have_key(chat.to_s)
      expect(described_class).not_to receive(:keep!)
      post { ok }
    end

    it "sends nothing when the chat keeps too much, rather than go on without it" do
      stub_const("#{described_class}::LIMIT_BYTES", 10)
      posted = false
      expect { post { posted = true } }.to raise_error(Monadic::Workbench::Look::Withheld, /too large/)
      expect(posted).to be(false)
      expect(message["workbench_picture"]).not_to have_key("sha256")
    end
  end

  describe "a post of a look's image" do
    let(:helper) { Class.new { include BaseVendorHelper }.new }
    let(:request_id) { Monadic::Workspace::Ids.generate(:request) }
    let(:session) { { chat_id: chat, parameters: { "app_name" => "ChatOpenAI" }, messages: [] } }
    let(:ledger) do
      Monadic::Workbench::Look::Ledger.for(chat, Monadic::Workspace::Chats.epoch(chat), request_id, session: session)
    end
    let(:ok) { double(status: HTTP::Response::Status.new(200)) }

    around do |example|
      Monadic::Workbench::Look::Ledger.reset!
      context = Monadic::Workspace::RequestContext.new(chat_id: chat, request_id: request_id)
      Monadic::Workspace::RequestContext.with(context) { example.run }
    end

    before do
      allow(Monadic::Utils::ModelSpec).to receive(:get_model_property).and_call_original
      allow(Monadic::Utils::ModelSpec).to receive(:get_model_property).with("m", "vision_capability").and_return(true)
      image = Monadic::Workbench::Look::ImageValue.checked(png("look"), source: "workbench_file")
      look = ledger.add(id: "look_#{'a' * 16}", item_id: "i_1", kind: "image", name: "a.png", path: "a.png",
                        version: "a" * 64, scope: "visible", image: image, result: "{}", caption: "x")
      ledger.bind(look, "c1")
      helper.workbench_looks_prepared([ledger.observations([look]).first])
    end

    def post(&block) = helper.post_with_workbench_looks(session, provider: "openai", model: "m", &block)

    it "keeps the image as it goes, pending until the reply's looks are let go" do
      expect(post { ok }).to eq(ok)
      sha = Digest::SHA256.hexdigest(png("look"))
      expect(files).to eq(["#{sha}.png"])
      expect(described_class::PENDING[chat.to_s]).to include(sha)
      ledger.close!
      expect(described_class::PENDING).not_to have_key(chat.to_s)
    end

    it "sends nothing when the chat keeps too much" do
      stub_const("#{described_class}::LIMIT_BYTES", 10)
      posted = false
      expect { post { posted = true } }.to raise_error(Monadic::Workbench::Look::Withheld, /too large/)
      expect(posted).to be(false)
    end

    it "sends the image without keeping it when the chat has no folder" do
      allow(described_class).to receive(:dir_for).and_return(nil)
      expect(post { ok }).to eq(ok)
      expect(described_class::PENDING).not_to have_key(chat.to_s)
    end
  end
end
