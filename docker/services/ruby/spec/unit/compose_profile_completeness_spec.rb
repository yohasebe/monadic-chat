# frozen_string_literal: true

require_relative '../spec_helper'
require 'yaml'

# Guards against drift between the Docker Compose profiles declared in
# docker/services/*/compose.yml and the profile sets in docker/monadic.sh.
#
# Background: the extractor service was added with its own profile but never
# wired into the start/stop lifecycle, so nothing started its container after
# an app restart and the Library import quality path silently fell back to
# pdfplumber (fixed in 8a8de720). Separately, teardown commands computed
# their profile list from feature flags, so a container started while a flag
# was on was orphaned once the flag was turned off. These tests make both
# classes of drift fail loudly when a profiled service is added or removed.
RSpec.describe 'Compose profile completeness in monadic.sh' do
  docker_dir = File.expand_path('../../../..', __dir__)
  monadic_sh_path = File.join(docker_dir, 'monadic.sh')

  let(:monadic_sh) { File.read(monadic_sh_path) }

  # Every profile declared by any service in docker/services/*/compose.yml.
  let(:declared_profiles) do
    Dir[File.join(docker_dir, 'services', '*', 'compose.yml')].flat_map do |path|
      yaml = YAML.safe_load(File.read(path), aliases: true)
      (yaml['services'] || {}).values.flat_map { |svc| svc['profiles'] || [] }
    end.uniq.sort
  end

  def profiles_in(definition_line)
    definition_line.scan(/--profile\s+([\w-]+)/).flatten.uniq.sort
  end

  describe 'ALL_PROFILES_DOWN (unconditional teardown set)' do
    it 'contains exactly the profiles declared in compose files' do
      line = monadic_sh[/^ALL_PROFILES_DOWN="[^"]*"/]
      expect(line).not_to be_nil,
        'ALL_PROFILES_DOWN definition not found in monadic.sh'

      down = profiles_in(line)
      expect(down).to eq(declared_profiles),
        "compose.yml only (add to ALL_PROFILES_DOWN): #{declared_profiles - down}\n" \
        "ALL_PROFILES_DOWN only (stale, remove): #{down - declared_profiles}"
    end

    it 'is a single unconditional assignment (never extended by feature flags)' do
      assignments = monadic_sh.scan(/^\s*ALL_PROFILES_DOWN=/).size
      expect(assignments).to eq(1),
        'ALL_PROFILES_DOWN must be assigned exactly once, unconditionally: ' \
        'feature flags gate startup, never teardown'
    end
  end

  describe 'ALL_PROFILES_UP (flag-gated startup set)' do
    it 'covers every declared profile across its assignments' do
      up = monadic_sh.scan(/^\s*ALL_PROFILES_UP="[^"]*"/)
                     .flat_map { |line| profiles_in(line) }.uniq.sort
      expect(up).to eq(declared_profiles),
        "compose.yml only (service never started — extractor-bug pattern): #{declared_profiles - up}\n" \
        "ALL_PROFILES_UP only (stale, remove): #{up - declared_profiles}"
    end
  end

  describe 'registry unification invariant' do
    # Since the ghcr.io unification (2026-06-13) every service image must
    # come from a registry under project control: ghcr.io/yohasebe/* for
    # prebuilt pulls, or a bare yohasebe/* name for images built locally on
    # the user's machine (ruby, python custom builds). A docker.io/upstream
    # reference here would silently reintroduce Docker Hub rate-limit
    # dependence and mutable-:latest risk at user install time.
    it 'compose files reference only project-controlled image names' do
      offenders = Dir[File.join(docker_dir, 'services', '*', 'compose.yml')].flat_map do |path|
        yaml = YAML.safe_load(File.read(path), aliases: true)
        (yaml['services'] || {}).flat_map do |name, svc|
          image = svc['image'].to_s
          next [] if image.empty?
          next [] if image.start_with?('ghcr.io/yohasebe/', 'yohasebe/')
          ["#{File.basename(File.dirname(path))}/compose.yml: #{name} -> #{image}"]
        end
      end
      expect(offenders).to be_empty,
        "compose image references outside the unified registries:\n#{offenders.join("\n")}"
    end
  end

  describe 'profile-set usage' do
    it 'never uses the flag-gated UP set for stop/down' do
      offenders = monadic_sh.each_line.with_index(1).select do |line, _|
        line.include?('${ALL_PROFILES_UP}') &&
          line.match?(/\s(down|stop)\b/)
      end.map { |_, n| "monadic.sh:#{n}" }
      expect(offenders).to be_empty,
        "stop/down must use ALL_PROFILES_DOWN (flags gate startup, not teardown): #{offenders.join(', ')}"
    end

    it 'never uses the unconditional DOWN set for up/pull/build' do
      offenders = monadic_sh.each_line.with_index(1).select do |line, _|
        line.include?('${ALL_PROFILES_DOWN}') &&
          line.match?(/\s(up|pull|build)\b/)
      end.map { |_, n| "monadic.sh:#{n}" }
      expect(offenders).to be_empty,
        "up/pull/build must use ALL_PROFILES_UP (disabled services must not be pulled or started): #{offenders.join(', ')}"
    end
  end
end
