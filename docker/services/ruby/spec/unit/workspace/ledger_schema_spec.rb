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

  it 'keeps artifacts and publications empty in this version (records there are refused)' do
    filled
    edit { |data| data['artifacts'][ids.generate(:artifact)] = {} }
    expect(error_of).to be_a(ledger_class::Shape)
    expect(error_of.message).to include('does not know')
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
