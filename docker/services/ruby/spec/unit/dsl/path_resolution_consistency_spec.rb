# frozen_string_literal: true

require 'spec_helper'

# Cross-cutting invariant: shared-volume path resolution must go through
# the canonical `Monadic::Utils::Environment.shared_volume` accessor
# (per CLAUDE.md "Dual-Mode Execution"), never through lexical
# `defined?(SHARED_VOL)` / `defined?(LOCAL_SHARED_VOL)` checks.
#
# Why this spec exists: the legacy `defined?(SHARED_VOL)` pattern silently
# fails in production whenever the calling module lives outside MonadicApp's
# lexical chain — Ruby's `defined?` does not walk the receiver's class
# hierarchy, only Module.nesting. Tests previously masked the bug by
# calling `stub_const("SHARED_VOL", ...)`, which creates a *top-level*
# constant visible from every module — a namespace that production code
# never enjoys. Three agents (`video_analyze_agent`, `audio_transcription_agent`,
# `image_analysis_agent`) carried this bug for ~8 months before it surfaced
# in Video Describer (commit `0403fc68` for the fix).
#
# This spec walks every production Ruby file under `lib/` and fails CI
# the moment a new occurrence of the anti-pattern is introduced.
RSpec.describe "Shared-volume path resolution consistency" do
  ROOT = File.expand_path("../../..", __dir__)

  # Files where the constants are legitimately defined or shadowed.
  EXEMPT_RELATIVE_PATHS = [
    "lib/monadic/app.rb"  # Defines SHARED_VOL / LOCAL_SHARED_VOL on MonadicApp
  ].freeze

  PRODUCTION_RUBY_FILES = Dir.glob(File.join(ROOT, "lib/**/*.rb")).freeze

  ANTI_PATTERN = /defined\?\(\s*(?:SHARED_VOL|LOCAL_SHARED_VOL)\s*\)/

  it "no production module relies on defined?(SHARED_VOL) / defined?(LOCAL_SHARED_VOL)" do
    offenders = PRODUCTION_RUBY_FILES.each_with_object([]) do |path, acc|
      relative = path.sub("#{ROOT}/", "")
      next if EXEMPT_RELATIVE_PATHS.include?(relative)

      content = File.read(path)
      next unless content =~ ANTI_PATTERN

      hits = content.lines.each_with_index.select { |line, _| line.match?(ANTI_PATTERN) }
      hits.each { |_, idx| acc << "#{relative}:#{idx + 1}" }
    end

    expect(offenders).to be_empty, <<~MSG
      The following lines use `defined?(SHARED_VOL)` or `defined?(LOCAL_SHARED_VOL)`,
      which never resolves outside MonadicApp's lexical scope and silently fails
      in production. Replace with `Monadic::Utils::Environment.shared_volume`
      (the canonical accessor — handles container vs. dev mode automatically).

      Offenders:
        #{offenders.join("\n  ")}
    MSG
  end
end
