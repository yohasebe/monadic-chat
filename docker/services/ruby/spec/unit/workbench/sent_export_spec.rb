# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "json"
require "base64"
require "digest"
require_relative "../../../lib/monadic/workspace"
require_relative "../../../lib/monadic/utils/websocket"
require_relative "../../../lib/monadic/workbench/sent"

# The images of the work screen a chat sent, in its export and back: the
# file holds those its messages name, in both kinds of file and as they
# are; a file's images are taken only as what they say, into the new chat.
RSpec.describe "The images a chat sent, in its export" do
  def png(salt = "")
    "\x89PNG\r\n\x1A\n".b + [13].pack("N") + "IHDR".b + [2, 2].pack("NN") + "\x08\x02\x00\x00\x00".b + "\x00".b * 4 + salt.b
  end

  around do |example|
    Dir.mktmpdir("sent-export-spec") do |dir|
      @data = File.join(dir, "data")
      @state = File.join(dir, "state")
      FileUtils.mkdir_p([@data, @state])
      @data = File.realpath(@data)
      example.run
    ensure
      words = Monadic::Utils::Privacy::Words
      words::LOCK.synchronize { words::TABLES.clear }
      sent::PENDING_LOCK.synchronize { sent::PENDING.clear }
    end
  end

  let(:sent) { Monadic::Workbench::Sent }
  let(:host) do
    Class.new do
      include WebSocketHelper
      def sent_out = (@sent_out ||= [])
      def send_to_client(_connection, payload) = sent_out << payload
    end.new
  end
  let(:session) do
    { messages: [], parameters: { "app_name" => "ChatOpenAI" } }.tap { |chat| Monadic::Workspace::Chats.start_new!(chat) }
  end
  let(:chat) { session[Monadic::Workspace::Chats::SESSION_KEY] }

  before do
    allow(Monadic::Utils::Environment).to receive(:data_path).and_return(@data)
    allow(Monadic::Utils::Environment).to receive(:state_path).and_return(@state)
  end

  # A look's image the chat sent, named by an assistant message.
  def looked(salt)
    sha = sent.keep!(chat, png(salt), "image/png", app_name: "ChatOpenAI")
    sent.done(chat, [sha])
    session[:messages] << { "mid" => SecureRandom.hex(4), "role" => "assistant", "text" => "seen",
                            "workbench_looks" => [{ "id" => "look_#{'a' * 16}", "item_id" => "i_1", "name" => "a.png",
                                                    "kind" => "image", "state" => "sent", "image_sha256" => sha }] }
    sha
  end

  def export(content)
    host.send(:handle_ws_privacy_export, :conn, session, { "encrypt" => false, "content" => content, "request_id" => "e1" })
    out = host.sent_out.last
    [out, out["content_base64"] && JSON.parse(Base64.strict_decode64(out["content_base64"]))]
  end

  describe "writing it" do
    it "holds each image the messages name as it is, in a restored file and in a masked one" do
      sha = looked("one")
      %w[restored masked].each do |content|
        out, file = export(content)
        expect(out).to include("type" => "privacy_export_data", "sent_images_missing" => 0)
        expect(Base64.strict_decode64(file.dig("sent_images", sha, "data"))).to eq(png("one"))
        expect(file.dig("sent_images", sha, "content_type")).to eq("image/png")
      end
    end

    it "keeps an image's sha256 as it is in a masked file, though a hidden word is in it" do
      sha = looked("two")
      Monadic::Utils::Privacy::Words.start!(session).confirm_all!([[sha[0, 6], "PERSON"]])
      _out, file = export("masked")
      expect(file["messages"].last["workbench_looks"].first["image_sha256"]).to eq(sha)
      expect(file["sent_images"].keys).to eq([sha])
    end

    it "says how many it could not hold, and holds none that is no longer the image" do
      sha = looked("three")
      File.binwrite(File.join(sent.dir_for(chat), "#{sha}.png"), png("changed"))
      out, file = export("restored")
      expect(out["sent_images_missing"]).to eq(1)
      expect(file).not_to have_key("sent_images")
      expect(file["sent_images_missing"]).to eq([sha])
    end

    it "is not written when the images are more than a file may hold" do
      looked("four")
      stub_const("#{sent}::EXPORT_LIMIT", 10)
      out, = export("restored")
      expect(out).to include("type" => "privacy_export_error", "error" => "too_large")
      expect(out["image_bytes"]).to be > 10
    end
  end

  describe "reading it" do
    let(:sha) { Digest::SHA256.hexdigest(png("one")) }
    let(:messages) { [{ "role" => "assistant", "workbench_looks" => [{ "state" => "sent", "image_sha256" => sha }] }] }
    let(:entry) { { "content_type" => "image/png", "data" => Base64.strict_encode64(png("one")) } }

    it "takes the images the messages name, as what they say" do
      table = { sha => entry, ("f" * 64) => entry }
      expect(sent.import_table(table, messages)).to eq(sha => { bytes: png("one"), content_type: "image/png" })
    end

    it "refuses a file whose image is not the one it names, not one, or not of its type" do
      [{ "content_type" => "image/png", "data" => Base64.strict_encode64(png("other")) },
       { "content_type" => "image/png", "data" => "not base64!" },
       { "content_type" => "image/jpeg", "data" => entry["data"] }].each do |bad|
        expect { sent.import_table({ sha => bad }, messages) }.to raise_error(sent::BadFile)
      end
    end

    it "puts the images in the new chat's folder when the import is taken" do
      images = sent.import_table({ sha => entry }, messages)
      %i[stop_speech_for_new_chat send_chat_to_page send_word_table sync_session_state!].each do |name|
        allow(host).to receive(name)
      end
      imported = { messages: messages, parameters: { "app_name" => "ChatOpenAI" }, sent_images: images }
      host.send(:handle_ws_import_apply, :conn, { "token" => "t1" }, session, imported)
      expect(host.sent_out.last).to include("type" => "import_result", "success" => true)
      expect(session).not_to have_key(:sent_images)
      expect(sent.read(session[Monadic::Workspace::Chats::SESSION_KEY], sha)).to eq(png("one"))
      expect(sent::PENDING).to be_empty
    end
  end
end
