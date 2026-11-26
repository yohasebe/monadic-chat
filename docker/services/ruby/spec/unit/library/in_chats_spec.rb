# frozen_string_literal: true

require 'spec_helper'
require 'monadic/library/in_chats'

RSpec.describe Monadic::Library::InChats do
  it 'is on unless the setting is "false"' do
    stub_const('CONFIG', {})
    expect(described_class.on?).to be true
    stub_const('CONFIG', { 'LIBRARY_IN_CHATS' => 'true' })
    expect(described_class.on?).to be true
    stub_const('CONFIG', { 'LIBRARY_IN_CHATS' => ' False ' })
    expect(described_class.on?).to be false
  end
end
