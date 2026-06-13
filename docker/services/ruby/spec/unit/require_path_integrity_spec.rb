# frozen_string_literal: true

require_relative '../spec_helper'

# Static integrity check: every `require_relative` target in the Ruby
# service must point at an existing file.
#
# Why this exists: the unit suite never loads `config.ru` (specs require
# lib files directly), so a file that is only referenced from the server
# boot path can be deleted with the whole suite staying green while
# `rake server:debug` / the production container die with a LoadError at
# startup. That exact failure shipped once: a "dead code" cleanup removed
# lib/monadic/utils/unlimited_session_store.rb, whose only consumer was
# config.ru line 8. This spec turns that class of breakage into a unit
# failure.
#
# Scope: static analysis only (no loading). Lines with string
# interpolation in the path are skipped — they cannot be resolved without
# executing the code.
RSpec.describe "require_relative path integrity" do
  ruby_root =
    if Dir.pwd.end_with?("docker/services/ruby")
      Dir.pwd
    else
      File.join(Dir.pwd, "docker", "services", "ruby")
    end

  # config.ru is the reason this spec exists; lib/ and apps/ are included
  # because the same static check is free and catches future cases where
  # a file's only consumer is itself lazily required.
  scanned_files = [File.join(ruby_root, "config.ru")] +
                  Dir.glob(File.join(ruby_root, "lib", "**", "*.rb")) +
                  Dir.glob(File.join(ruby_root, "apps", "**", "*.rb"))

  it "scans a sane number of files" do
    expect(scanned_files.size).to be > 100
  end

  it "finds an existing file for every require_relative" do
    missing = []

    scanned_files.each do |file|
      File.foreach(file).with_index(1) do |line, lineno|
        match = line.match(/^\s*require_relative\s+["']([^"']+)["']/)
        next unless match

        target = match[1]
        next if target.include?('#{') # dynamic path — not statically resolvable

        base = File.expand_path(target, File.dirname(file))
        next if File.exist?("#{base}.rb") || File.exist?(base)

        missing << "#{file.sub("#{ruby_root}/", '')}:#{lineno} → #{target}"
      end
    end

    expect(missing).to be_empty, <<~MSG
      require_relative targets that do not exist on disk (deleting a file
      whose only consumer is config.ru or a lazily-required path breaks
      server boot while unit specs stay green):
      #{missing.join("\n")}
    MSG
  end
end
