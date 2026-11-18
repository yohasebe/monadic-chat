# frozen_string_literal: true

require 'spec_helper'

# The specs never change the shared folder of the person running them.
RSpec.describe 'RealSharedFolderGuard' do
  it 'stops a write into the real shared folder before anything is written' do
    real = File.join(RealSharedFolderGuard::FOLDER, 'guard-probe-never-written.txt')
    expect { Monadic::Utils::SharedPathGuard.write_file!(real, 'x') }.to raise_error(/user's shared folder/)
    expect(File.exist?(real)).to be(false)
  end

  it 'lets a write into a folder of the spec through' do
    Dir.mktmpdir do |dir|
      allow(Monadic::Utils::Environment).to receive(:data_path).and_return(File.realpath(dir))
      Monadic::Utils::SharedPathGuard.write_file!(File.join(File.realpath(dir), 'a.txt'), 'x')
      expect(File.read(File.join(dir, 'a.txt'))).to eq('x')
    end
  end
end
