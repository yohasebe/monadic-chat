# frozen_string_literal: true

require_relative "../../spec_helper"
require "tmpdir"
require_relative "../../../lib/monadic/workspace/ids"
require_relative "../../../lib/monadic/workbench/channel"
require_relative "../../../lib/monadic/workbench/media_item"

# A video, audio or MIDI file of the work screen a tool reads, named by the
# item's id: of the kinds the tool takes, still the version on the work
# screen; a file the user put there as its attachment, one opened from the
# shared folder by its path.
RSpec.describe Monadic::Workbench::MediaItem do
  around do |example|
    Dir.mktmpdir("media-item-spec") do |dir|
      @data = File.join(dir, "data")
      @state = File.join(dir, "state")
      FileUtils.mkdir_p([@data, @state])
      @data = File.realpath(@data)
      example.run
    end
  end

  let(:store) { Monadic::Workbench::Store.new(File.join(@state, "workbench")) }
  let(:chat) { Monadic::Workspace::Ids.generate(:chat) }
  let(:origin) { { actor: :user, source: :panel, tab: "tab-1", generation: 1 } }
  let(:workbench) { Struct.new(:chat_id).new(chat) }

  before do
    Monadic::Workbench::Board.reset!
    Monadic::Workbench::Board.live = ->(t) { t == "tab-1" ? 1 : nil }
    allow(Monadic::Workbench::Store).to receive(:default).and_return(store)
    allow(Monadic::Utils::Environment).to receive(:data_path).and_return(@data)
    allow(Monadic::Utils::Environment).to receive(:state_path).and_return(@state)
    allow(Monadic::Workbench::Channel).to receive(:changed)
  end

  after { Monadic::Workspace::Ledger.clear_unsettled! }

  def put(name, bytes, attachment_id: nil)
    File.binwrite(File.join(@data, name), bytes)
    item, = Monadic::Workbench::Board.for(chat, store: store)
                                     .add_file(path: name, origin: origin, epoch: Monadic::Workspace::Chats.epoch(chat),
                                               attachment_id: attachment_id)
    item
  end

  let(:mp3) { "ID3\x04\x00\x00\x00\x00\x00\x00 a song".b }
  let(:midi) { "MThd\x00\x00\x00\x06 a tune".b }

  it "gives a file opened from the shared folder by its path, for a tool that takes its kind" do
    song = put("song.mp3", mp3)
    expect(described_class.resolve(workbench, song["id"], kinds: %w[audio])).to eq(path: "song.mp3")
    tune = put("tune.mid", midi)
    expect(described_class.resolve(workbench, tune["id"], kinds: %w[audio midi])).to eq(path: "tune.mid")
    expect { described_class.resolve(workbench, tune["id"], kinds: %w[audio]) }
      .to raise_error(described_class::Refused, /not audio/)
    expect { described_class.resolve(workbench, song["id"], kinds: %w[video]) }.to raise_error(described_class::Refused)
  end

  it "refuses an item not on the work screen, one changed after it was put there, and a reply without a work screen" do
    song = put("song.mp3", mp3)
    expect { described_class.resolve(workbench, "i_gone", kinds: %w[audio]) }.to raise_error(described_class::Refused, /not on the work screen/)
    expect { described_class.resolve(nil, song["id"], kinds: %w[audio]) }.to raise_error(described_class::Refused)
    File.binwrite(File.join(@data, "song.mp3"), "ID3\x04\x00\x00\x00\x00\x00\x00 another song".b)
    expect { described_class.resolve(workbench, song["id"], kinds: %w[audio]) }.to raise_error(described_class::Refused, /changed/)
  end

  it "gives a file the user put there as its attachment's record, only while it is that version" do
    id = Monadic::Workspace::Ids.generate(:attachment)
    song = put("song.mp3", mp3, attachment_id: id)
    record = { attachment_id: id, sha256: song.dig("file", "sha256"), path: File.join(@data, "song.mp3") }
    allow(Monadic::Workspace::Attachments).to receive(:resolve!).with(chat_id: chat, attachment_id: id).and_return(record)
    expect(described_class.resolve(workbench, song["id"], kinds: %w[audio])).to eq(record: record)
    allow(Monadic::Workspace::Attachments).to receive(:resolve!).and_return(record.merge(sha256: "0" * 64))
    expect { described_class.resolve(workbench, song["id"], kinds: %w[audio]) }.to raise_error(described_class::Refused, /changed/)
    allow(Monadic::Workspace::Attachments).to receive(:resolve!)
      .and_raise(Monadic::Workspace::Attachments::Unusable.new(:missing, "The attached file is no longer in the shared folder."))
    expect { described_class.resolve(workbench, song["id"], kinds: %w[audio]) }.to raise_error(described_class::Refused, /no longer/)
  end
end
