# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../lib/monadic/utils/environment'

RSpec.describe Monadic::Utils::Environment do
  before do
    allow(File).to receive(:file?).and_call_original
    allow(File).to receive(:file?).with('/.dockerenv').and_return(false)
    allow(File).to receive(:file?).with('/run/.containerenv').and_return(false)
  end

  it 'knows a container by the file Docker puts in it' do
    allow(File).to receive(:file?).with('/.dockerenv').and_return(true)
    expect(described_class.container_marker?).to be(true)
  end

  it 'knows a container by the file Podman puts in it' do
    allow(File).to receive(:file?).with('/run/.containerenv').and_return(true)
    expect(described_class.container_marker?).to be(true)
  end

  it 'is not in a container without either file' do
    expect(described_class.container_marker?).to be(false)
  end
end
