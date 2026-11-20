# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'docker builds in monadic.sh' do
  let(:script) { File.read(File.expand_path('../../../../monadic.sh', __dir__)) }

  it 'puts each image it builds into the engine' do
    builds = script.lines.grep(/\$\{DOCKER\} build\b/).reject { |line| line.strip.start_with?('#') }
    expect(builds).not_to be_empty
    expect(builds).to all(include('--load'))
  end

  it 'runs every engine command through the CLI it resolved' do
    commands = %w[rmi ps exec images compose run build pull info version inspect start stop rm volume network image container context]
    bare = script.lines.reject { |line| line.strip.start_with?('#') || line.include?('echo ') }
                 .grep(/(^|[;&|(]|\s)docker (#{commands.join('|')})\b/)
    expect(bare).to eq([])
  end
end
