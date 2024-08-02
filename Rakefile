# frozen_string_literal: true

require "fileutils"
require "rspec/core/rake_task"
require_relative "./docker/services/ruby/lib/monadic/version"
version = Monadic::VERSION

RSpec::Core::RakeTask.new(:spec)

require "rubocop/rake_task"

RuboCop::RakeTask.new

task default: %i[spec rubocop]

task :eslint do
  sh "npx eslint ."
end

# task to build win/mac x64/mac arm64 packages
task :build do
  home_directory_path = File.join(File.dirname(__FILE__), "docker")
  Dir.glob("#{home_directory_path}/data/*").each { |file| FileUtils.rm_f(file) }
  Dir.glob("#{home_directory_path}/dist/*").each { |file| FileUtils.rm_f(file) }

  sh "npm run build:linux-x64"
  sh "npm run build:linux-arm64"
  sh "npm run build:win"
  sh "npm run build:mac-x64"
  sh "npm run build:mac-arm64"

  necessary_files = [
    "Monadic Chat-#{version}-arm64.dmg",
    "Monadic Chat-#{version}.dmg",
    "Monadic Chat Setup #{version}.exe",
    "monadic-chat_#{version}_amd64.deb",
    "monadic-chat_#{version}_arm64.deb"
  ].map { |file| File.expand_path("dist/#{file}") }

  Dir.glob("dist/*").each do |file|
    filepath = File.expand_path(file)
    FileUtils.rm_rf(filepath) unless necessary_files.include?(filepath)
    # move the file to the /docs/assets/download/ directory if it is included in necessar_files
    # FileUtils.mv(filepath, "docs/assets/download/") if necessary_files.include?(filepath)
  end
end
