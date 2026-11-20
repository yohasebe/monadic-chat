# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'docker builds in monadic.sh' do
  let(:script) { File.read(File.expand_path('../../../../monadic.sh', __dir__)) }

  it 'puts each image it builds into the engine' do
    builds = script.lines.grep(/\$\{DOCKER\} build\b/).reject { |line| line.strip.start_with?('#') }
    expect(builds).not_to be_empty
    expect(builds).to all(include('--load'))
  end
end
