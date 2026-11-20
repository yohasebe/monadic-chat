# frozen_string_literal: true

require 'spec_helper'
require 'yaml'

RSpec.describe 'settings every Docker-compatible engine takes' do
  it 'sets only the mode and size of the secrets tmpfs' do
    compose = YAML.safe_load(File.read(File.join(__dir__, '../../compose.yml')))
    mount = compose.dig('services', 'ruby_service', 'tmpfs').find { |m| m.start_with?('/run/monadic-secrets:') }
    options = mount.split(':', 2).last.split(',').map { |o| o.split('=').first }
    expect(options).to contain_exactly('mode', 'size')
  end

  it 'lets the Ruby container reach the engine socket where SELinux confines containers' do
    compose = YAML.safe_load(File.read(File.join(__dir__, '../../compose.yml')))
    expect(compose.dig('services', 'ruby_service', 'security_opt')).to include('label=disable')
  end
end
