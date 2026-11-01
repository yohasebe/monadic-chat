# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'json'
require_relative '../../../lib/monadic/workspace'

# The ledger is checked whenever it is read and before a change is saved, so
# a ledger out of form is refused (nothing is registered from it) and a
# change that would put it out of form is not saved.
RSpec.describe Monadic::Workspace::LedgerSchema do
  around do |example|
    Dir.mktmpdir('ledger-schema') do |dir|
      @dir = dir
      example.run
    end
  end

  let(:path) { File.join(@dir, 'ledger.json') }
  let(:ledger) { Monadic::Workspace::Ledger.new(path) }
  let(:ids) { Monadic::Workspace::Ids }
  let(:ledger_class) { Monadic::Workspace::Ledger }

  # A ledger as the code writes it: a chat with its workspace and an
  # attachment of each state.
  def filled
    chat = ids.generate(:chat)
    workspace = ids.generate(:workspace)
    dir = "conversations/20261021-120000_chat_#{workspace}"
    ledger.register_workspace(chat_id: chat, workspace_id: workspace, app_name: 'Chat', relative_dir: dir)
    made = %w[ready failed validating].to_h do |state|
      id = ids.generate(:attachment)
      ledger.register_attachment(attachment_id: id, chat_id: chat, workspace_id: workspace, purpose: 'video',
                                 original_name: 'v.mp4', relative_path: "#{dir}/inputs/#{id}__v.mp4")
      ledger.update_attachment(id, status: 'ready', 'size' => 10, 'sha256' => 'a' * 64) if state == 'ready'
      ledger.update_attachment(id, status: 'failed', 'failure' => 'Interrupted') if state == 'failed'
      [state, id]
    end
    { chat: chat, workspace: workspace, dir: dir, attachments: made }
  end

  def edit
    data = JSON.parse(File.read(path))
    yield data
    File.write(path, JSON.generate(data))
  end

  def error_of
    ledger.snapshot
    nil
  rescue ledger_class::Unreadable => e
    e
  end

  it 'takes a ledger as the code writes it, with every collection' do
    made = filled
    data = JSON.parse(File.read(path))
    expect(data.keys).to include('schema_version', 'chats', 'workspaces', 'attachments', 'artifacts', 'publications')
    expect(ledger.attachment(made[:attachments]['ready'])[:status]).to eq('ready')
  end

  it 'takes a version 1 ledger (without artifacts and publications) in the current form, and a version 2 one only with them' do
    filled
    edit { |data| data.delete('artifacts'); data.delete('publications'); data['schema_version'] = 1 }
    expect(error_of).to be_nil
    edit { |data| data['schema_version'] = 2 }
    expect(error_of).to be_a(ledger_class::Shape)
  end

  describe 'publications' do
    def published(made, status: 'ready')
      id = ids.generate(:publication)
      record = ledger.reserve_publication(publication_id: id, name: "pub_#{id.delete_prefix('p_')}.mp4", token: 'c' * 16,
                                          kind: 'attachment', id: made[:attachments]['ready'], cap_bytes: 1000)
      ledger.settle_publication(id, 'c' * 16) if status == 'ready'
      record
    end

    it 'takes a publication of a ready attachment, pending with its token or ready without one' do
      made = filled
      record = published(made, status: 'pending')
      expect(record).to include(status: 'pending', size: 10, sha256: 'a' * 64, content_type: 'video/mp4', chat_id: made[:chat])
      expect(error_of).to be_nil
      expect(ledger.settle_publication(record[:publication_id], 'c' * 16)).to include(status: 'ready')
      expect(error_of).to be_nil
    end

    {
      'a name not of the public form' => ->(r) { r['name'] = 'video.mp4' },
      'a name not made from its id' => ->(r) { r['name'] = "pub_#{'b' * 16}.mp4" },
      'an extension not published' => ->(r) { r['name'] = r['name'].sub('.mp4', '.exe') },
      'a type that does not go with the name' => ->(r) { r['content_type'] = 'text/html' },
      'a source sha256 that is not its source\'s' => ->(r) { r['source']['sha256'] = 'd' * 64 },
      'a size that is not its source\'s' => ->(r) { r['size'] = 11 },
      'an unknown status' => ->(r) { r['status'] = 'served' },
      'a token on a ready record' => ->(r) { r['token'] = 'c' * 16 },
      'an unknown source kind' => ->(r) { r['source']['kind'] = 'file' },
      'another chat' => ->(r) { r['chat_id'] = Monadic::Workspace::Ids.generate(:chat) }
    }.each do |what, change|
      it "refuses #{what}" do
        made = filled
        record = published(made)
        edit { |data| change.call(data['publications'][record[:publication_id]]) }
        expect(error_of).to be_a(ledger_class::Shape)
      end
    end

    it 'refuses a pending record without its token, a source that is not ready, and two live ones of one source' do
      made = filled
      record = published(made)
      edit { |data| data['publications'][record[:publication_id]].merge!('status' => 'pending') }
      expect(error_of).to be_a(ledger_class::Shape)
      edit { |data| data['publications'][record[:publication_id]].merge!('status' => 'ready', 'source' => { 'kind' => 'attachment', 'id' => made[:attachments]['failed'], 'sha256' => 'a' * 64 }) }
      expect(error_of).to be_a(ledger_class::Shape)
      edit do |data|
        first = data['publications'][record[:publication_id]]
        first['source']['id'] = made[:attachments]['ready']
        other = ids.generate(:publication)
        data['publications'][other] = first.merge('name' => "pub_#{other.delete_prefix('p_')}.mp4")
      end
      expect(error_of).to be_a(ledger_class::Shape)
    end

    it 'records a source once while it is pending or ready, and within the room allowed' do
      made = filled
      record = published(made, status: 'pending')
      expect do
        other = ids.generate(:publication)
        ledger.reserve_publication(publication_id: other, name: "pub_#{other.delete_prefix('p_')}.mp4", token: 'd' * 16,
                                   kind: 'attachment', id: made[:attachments]['ready'], cap_bytes: 1000)
      end.to raise_error(ledger_class::Conflict)
      ledger.drop_publication(record[:publication_id], 'c' * 16)
      expect do
        other = ids.generate(:publication)
        ledger.reserve_publication(publication_id: other, name: "pub_#{other.delete_prefix('p_')}.mp4", token: 'd' * 16,
                                   kind: 'attachment', id: made[:attachments]['ready'], cap_bytes: 9)
      end.to raise_error(ledger_class::Full)
    end

    it 'makes ready only the pending record of the operation that holds its token, never a revoked one' do
      made = filled
      record = published(made, status: 'pending')
      expect { ledger.settle_publication(record[:publication_id], 'x' * 16) }.to raise_error(ledger_class::Conflict)
      expect(ledger.mark_publication(record[:publication_id], status: 'revoked', from: %w[pending ready])).to be(true)
      expect { ledger.settle_publication(record[:publication_id], 'c' * 16) }.to raise_error(ledger_class::Conflict)
      expect(ledger.publication_named(record[:name])[:status]).to eq('revoked')
    end
  end

  describe 'artifacts' do
    let(:job) { ids.generate(:job) }

    def chat_artifact(made)
      ledger.register_artifact(artifact_id: ids.generate(:artifact), owner: { kind: :chat, workspace_id: made[:workspace] },
                               job_id: job, kind: 'subtitle_vtt', size: 5, sha256: 'b' * 64)
    end

    def outside_artifact
      ledger.register_artifact(artifact_id: ids.generate(:artifact), owner: { kind: :outside, root: 'transcriptions' },
                               job_id: job, kind: 'subtitle_srt', size: 0, sha256: 'c' * 64)
    end

    it 'records one of a chat in its run folder, taking the chat from the ledger, and one outside any chat' do
      made = filled
      record = chat_artifact(made)
      expect(record).to include(owner: 'chat', chat_id: made[:chat], workspace_id: made[:workspace], status: 'ready',
                                copy_path: "#{made[:dir]}/artifacts/#{job}/transcript.vtt")
      outside = outside_artifact
      expect(outside).to include(owner: 'outside', root: 'transcriptions', copy_path: "transcriptions/artifacts/#{job}/transcript.srt")
      expect(outside).not_to include(:chat_id, :workspace_id)
    end

    it 'refuses an owner that is not in the ledger or not known, and a root not set aside for runs outside chats' do
      filled
      before = File.read(path)
      expect { chat_artifact(workspace: ids.generate(:workspace)) }.to raise_error(ledger_class::Conflict)
      expect do
        ledger.register_artifact(artifact_id: ids.generate(:artifact), owner: { kind: :outside, root: 'conversations' },
                                 job_id: job, kind: 'subtitle_vtt', size: 1, sha256: 'b' * 64)
      end.to raise_error(ledger_class::Shape)
      expect do
        ledger.register_artifact(artifact_id: ids.generate(:artifact), owner: { kind: :someone },
                                 job_id: job, kind: 'subtitle_vtt', size: 1, sha256: 'b' * 64)
      end.to raise_error(ArgumentError)
      expect do
        ledger.register_artifact(artifact_id: 'r_x', owner: { kind: :outside, root: 'transcriptions' },
                                 job_id: job, kind: 'subtitle_vtt', size: 1, sha256: 'b' * 64)
      end.to raise_error(ArgumentError)
      expect(File.read(path)).to eq(before)
    end

    it 'refuses an artifact out of form, naming the field and no id' do
      made = filled
      record = chat_artifact(made)
      id = record[:artifact_id]
      outside = outside_artifact[:artifact_id]
      breaks = {
        'an unknown owner' => ->(d) { d['artifacts'][id]['owner'] = 'user' },
        'a chat that is not its workspace\'s' => ->(d) { d['artifacts'][id]['chat_id'] = ids.generate(:chat) },
        'a workspace that is not in the ledger' => ->(d) { d['artifacts'][id]['workspace_id'] = ids.generate(:workspace) },
        'a chat artifact with a root' => ->(d) { d['artifacts'][id]['root'] = 'transcriptions' },
        'an outside artifact with a chat' => ->(d) { d['artifacts'][outside]['chat_id'] = made[:chat] },
        'an outside artifact with a null workspace' => ->(d) { d['artifacts'][outside]['workspace_id'] = nil },
        'a root not set aside' => ->(d) { d['artifacts'][outside]['root'] = 'conversations' },
        'a job id of the wrong kind' => ->(d) { d['artifacts'][id]['job_id'] = made[:workspace] },
        'an unknown kind' => ->(d) { d['artifacts'][id]['kind'] = 'image' },
        'a copy in another job' => ->(d) { d['artifacts'][id]['copy_path'] = "#{made[:dir]}/artifacts/#{ids.generate(:job)}/transcript.vtt" },
        'a copy one level down' => ->(d) { d['artifacts'][id]['copy_path'] = "#{made[:dir]}/artifacts/#{job}/x/transcript.vtt" },
        'a copy spelled another way' => ->(d) { d['artifacts'][id]['copy_path'] = "#{made[:dir]}/artifacts/./#{job}/transcript.vtt" },
        'a copy of the other kind\'s name' => ->(d) { d['artifacts'][id]['copy_path'] = "#{made[:dir]}/artifacts/#{job}/transcript.srt" },
        'a copy in another chat\'s folder' => ->(d) { d['artifacts'][id]['copy_path'] = "conversations/other/artifacts/#{job}/transcript.vtt" },
        'no size' => ->(d) { d['artifacts'][id].delete('size') },
        'no sha256' => ->(d) { d['artifacts'][id].delete('sha256') },
        'a sha256 of the wrong form' => ->(d) { d['artifacts'][id]['sha256'] = 'B' * 64 },
        'a state other than ready' => ->(d) { d['artifacts'][id]['status'] = 'pending' },
        'a time that is not a time' => ->(d) { d['artifacts'][id]['created_at'] = nil },
        'a key of the wrong kind' => ->(d) { d['artifacts']["p_#{'a' * 16}"] = d['artifacts'].delete(id) }
      }
      original = File.read(path)
      breaks.each do |label, change|
        File.write(path, original)
        edit { |data| change.call(data) }
        error = error_of
        expect(error).to be_a(ledger_class::Shape), label
        [made[:chat], made[:workspace], id, job].each { |secret| expect(error.message).not_to include(secret) }
      end
    end
  end

  it 'keeps fields and collections it does not know (a later version may add them), through a change too' do
    made_validating = filled[:attachments]['validating']
    edit do |data|
      data['later'] = { 'x' => 1 }
      data['chats'].each_value { |chat| chat['later'] = true }
    end
    expect(error_of).to be_nil
    ledger.update_attachment(made_validating, status: 'failed', 'failure' => 'Interrupted')
    data = JSON.parse(File.read(path))
    expect(data['later']).to eq('x' => 1)
    expect(data['chats'].values).to all(include('later' => true))
  end

  it 'tells JSON that cannot be read from a ledger out of form and from a newer one' do
    File.write(path, '{')
    expect(error_of).to be_a(ledger_class::Syntax)
    File.write(path, JSON.generate('schema_version' => 3))
    expect(error_of).to be_a(ledger_class::Newer)
    File.write(path, JSON.generate('schema_version' => '1'))
    expect(error_of).to be_a(ledger_class::Shape)
    File.write(path, '[]')
    expect(error_of).to be_a(ledger_class::Shape)
    File.write(path, JSON.generate('schema_version' => nil))
    expect(error_of).to be_a(ledger_class::Shape)
  end

  it 'takes no null or false for a collection or a field, only a missing one' do
    made = filled
    original = File.read(path)
    validating = made[:attachments]['validating']
    breaks = Monadic::Workspace::LedgerSchema::COLLECTIONS.flat_map do |name|
      [->(d) { d[name] = nil }, ->(d) { d[name] = false }]
    end
    breaks += [->(d) { d['attachments'][validating]['size'] = nil },
               ->(d) { d['attachments'][validating]['sha256'] = nil }]
    breaks.each_with_index do |change, i|
      File.write(path, original)
      edit { |data| change.call(data) }
      expect(error_of).to be_a(ledger_class::Shape), "break #{i}"
      broken = File.read(path)
      expect { ledger.update_attachment(validating, status: 'failed', 'failure' => 'X') }
        .to raise_error(ledger_class::Shape)
      expect(File.read(path)).to eq(broken)
    end
  end

  it 'refuses a ledger out of form, naming the field and no id or name' do
    made = filled
    ready = made[:attachments]['ready']
    breaks = {
      'no version with records' => ->(d) { d.delete('schema_version') },
      'a collection that is not an object' => ->(d) { d['attachments'] = [] },
      'a key of the wrong kind' => ->(d) { d['chats']["w_#{'a' * 16}"] = d['chats'].delete(made[:chat]) },
      'a chat pointing elsewhere' => ->(d) { d['chats'][made[:chat]]['workspace_id'] = ids.generate(:workspace) },
      'a workspace pointing elsewhere' => ->(d) { d['workspaces'][made[:workspace]]['chat_id'] = ids.generate(:chat) },
      'a folder outside' => ->(d) { d['workspaces'][made[:workspace]]['relative_dir'] = '../elsewhere' },
      'an absolute folder' => ->(d) { d['workspaces'][made[:workspace]]['relative_dir'] = '/etc' },
      'an attachment of another workspace' => ->(d) { d['attachments'][ready]['workspace_id'] = ids.generate(:workspace) },
      'an attachment outside its folder' => ->(d) { d['attachments'][ready]['relative_path'] = 'conversations/other/x.mp4' },
      'an unknown state' => ->(d) { d['attachments'][ready]['status'] = 'usable' },
      'a ready attachment without sha256' => ->(d) { d['attachments'][ready].delete('sha256') },
      'a ready attachment without size' => ->(d) { d['attachments'][ready].delete('size') },
      'a size that is not a count' => ->(d) { d['attachments'][ready]['size'] = -1 },
      'a sha256 of the wrong form' => ->(d) { d['attachments'][ready]['sha256'] = 'abc' },
      'a time that is not a time' => ->(d) { d['attachments'][ready]['created_at'] = 'yesterday' },
      'a name that is not text' => ->(d) { d['attachments'][ready]['original_name'] = 1 },
      'a publication key of the wrong kind' => ->(d) { d['publications']['pub_x'] = {} },
      'a version 2 ledger without a collection' => ->(d) { d.delete('chats') },
      'a chat whose workspace is gone' => lambda do |d|
        d['workspaces'].delete(made[:workspace])
        d['attachments'].clear
      end,
      'a workspace whose chat is gone' => ->(d) { d['chats'].delete(made[:chat]) }
    }
    original = File.read(path)
    breaks.each do |label, change|
      File.write(path, original)
      edit { |data| change.call(data) }
      error = error_of
      expect(error).to be_a(ledger_class::Shape), label
      [made[:chat], made[:workspace], ready, 'v.mp4'].each { |secret| expect(error.message).not_to include(secret) }
    end
  end

  it 'does not save a change that would put the ledger out of form' do
    made = filled
    before = File.read(path)
    expect { ledger.update_attachment(made[:attachments]['validating'], status: 'ready') }
      .to raise_error(ledger_class::Shape, /no size/)
    expect(File.read(path)).to eq(before)
  end

  it 'refuses registering anything from a ledger it cannot use' do
    filled
    edit { |data| data['attachments'].each_value { |r| r['status'] = 'usable' } }
    expect do
      ledger.register_workspace(chat_id: ids.generate(:chat), workspace_id: ids.generate(:workspace), app_name: 'Chat',
                                relative_dir: 'conversations/new')
    end.to raise_error(ledger_class::Shape)
  end
end
