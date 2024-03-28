# frozen_string_literal: true

require 'fileutils'
require "rspec/core/rake_task"
require_relative "./server/docker/ruby/lib/monadic/version"
version = Monadic::VERSION

RSpec::Core::RakeTask.new(:spec)

require "rubocop/rake_task"

RuboCop::RakeTask.new

task default: %i[spec rubocop]

# task to build win/mac x64/mac arm64 packages
task :build do

  home_directory_path = File.join(File.dirname(__FILE__), "server")
  Dir.glob("#{home_directory_path}/data/*").each { |file| FileUtils.rm_f(file) }
  Dir.glob("#{home_directory_path}/dist/*").each { |file| FileUtils.rm_f(file) }

  # sh "npm run build:linux"
  sh "npm run build:win"
  sh "npm run build:mac-x64"
  sh "npm run build:mac-arm64"

  necessary_files = [
    "monadic-chat-#{version}-arm64.dmg",
    "monadic-chat-#{version}.dmg",
    "monadic-chat Setup #{version}.exe",
    # "monadic-chat_#{version}_amd64.deb",
  ].map { |file| File.expand_path("dist/#{file}") }

  Dir.glob("dist/*").each do |file|
    filepath = File.expand_path(file)
    FileUtils.rm_rf(filepath) unless necessary_files.include?(filepath)
  end
end
