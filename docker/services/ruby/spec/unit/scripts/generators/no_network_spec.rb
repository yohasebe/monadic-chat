# frozen_string_literal: true

require 'spec_helper'

# Generator scripts talk to paid APIs. A unit spec that SPAWNS one runs the
# real thing: `image_generator_grok.rb -p "test prompt"` generated an image and
# billed for it on every full unit run (2026-08-18), and the OpenAI spec stayed
# free only because the example.com URL it passed happened to 404 — its safety
# depended on an external site.
#
# The fix is structural: every generator script now carries a
# `__FILE__ == $PROGRAM_NAME` guard, so specs require it and exercise the
# functions in-process, where HTTP can be stubbed. With no subprocess there is
# nothing that can reach the network behind the suite's back.
#
# This spec fails if a generator spec starts spawning again, or if a script
# loses its guard.
RSpec.describe "generator specs stay offline" do
  spec_dir = __dir__
  script_dir = File.expand_path("../../../../scripts/generators", __dir__)

  SPAWNERS = [
    /\bOpen3\./,
    /\bsystem\(/,
    /\bexec\(/,
    /\bspawn\(/,
    /`[^`]*ruby[^`]*`/,
    /IO\.popen/
  ].freeze

  it "does not spawn subprocesses from generator specs" do
    offenders = Dir[File.join(spec_dir, "*_spec.rb")].flat_map do |path|
      next [] if File.basename(path) == File.basename(__FILE__)

      File.readlines(path).each_with_index.filter_map do |line, i|
        next if line.strip.start_with?("#")
        next unless SPAWNERS.any? { |re| line.match?(re) }

        "#{File.basename(path)}:#{i + 1}: #{line.strip}"
      end
    end

    expect(offenders).to be_empty, <<~MSG
      A generator spec spawns the script as a subprocess, which runs the real
      paid API:

        #{offenders.join("\n  ")}

      Require the script instead (it has a __FILE__ guard) and call its
      functions, stubbing HTTP where a request would be made.
    MSG
  end

  it "loads every generator script through the namespacing loader" do
    offenders = Dir[File.join(spec_dir, "*_spec.rb")].filter_map do |path|
      body = File.read(path)
      next if body.include?("GeneratorScriptLoader.load")
      next unless body.match?(/require(_relative)?\s+.*scripts\/generators/) || body.include?("require script_path")

      File.basename(path)
    end

    expect(offenders).to be_empty, <<~MSG
      These specs require a generator script directly. Top-level defs land on
      Object, so the last script loaded overwrites the others' get_api_key,
      generate_image and friends — specs then test the wrong script:

        #{offenders.join("\n  ")}

      Use GeneratorScriptLoader.load("name.rb"), which evaluates it in its own
      namespace.
    MSG
  end

  it "keeps every generator script's helpers off Object" do
    before = Object.instance_methods(false) | Object.private_instance_methods(false)
    Dir[File.join(script_dir, "*.rb")].each do |path|
      # A script without the guard runs its CLI on load and calls exit, which
      # would abort the whole rspec process instead of reporting. The guard
      # check below is the one that should speak up about those.
      next unless File.read(path).include?("__FILE__ == $PROGRAM_NAME")

      GeneratorScriptLoader.load(File.basename(path))
    end
    leaked = (Object.instance_methods(false) | Object.private_instance_methods(false)) - before

    expect(leaked).to be_empty,
                      "Loading the generator scripts defined #{leaked.inspect} on Object; " \
                      "another spec calling one of those names would silently get this script's version."
  end

  it "keeps the __FILE__ guard on every generator script" do
    unguarded = Dir[File.join(script_dir, "*.rb")].reject do |path|
      File.read(path).include?("__FILE__ == $PROGRAM_NAME")
    end.map { |path| File.basename(path) }

    expect(unguarded).to be_empty, <<~MSG
      These generator scripts run their CLI at load time, so a spec cannot
      require them without executing the whole thing:

        #{unguarded.join("\n  ")}

      Wrap the argument parsing and the final invocation in
      `if __FILE__ == $PROGRAM_NAME ... end`.
    MSG
  end
end
