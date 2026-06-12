# frozen_string_literal: true

require_relative '../spec_helper'

# Guards the cross-process output contracts between docker/monadic.sh
# (producer) and its two consumers: the Electron main process
# (app/main.js, matching on output.includes(...)) and the Ruby backend
# (lib/monadic/utils/container_dependencies.rb, matching ensure-service
# statuses). These signals are plain strings over stdout, so nothing but
# a test pins them: renaming an echo in monadic.sh silently breaks the
# consumer (the original extractor bug pattern — everything stays green
# while a feature dies).
#
# The canonical marker lists live HERE; both sides are asserted to
# reference them, mirroring the tts_registry_sync_spec approach.
RSpec.describe 'Process output contracts (monadic.sh <-> consumers)' do
  docker_dir = File.expand_path('../../../..', __dir__)
  repo_root = File.expand_path('..', docker_dir)

  let(:monadic_sh) { File.read(File.join(docker_dir, 'monadic.sh')) }
  let(:main_js) { File.read(File.join(repo_root, 'app', 'main.js')) }
  let(:container_deps) do
    File.read(File.join(docker_dir, 'services', 'ruby', 'lib', 'monadic',
                        'utils', 'container_dependencies.rb'))
  end

  describe 'ensure-service status tokens' do
    # The Ruby consumer handles: STARTED / ALREADY_RUNNING / *_DISABLED /
    # *_NOT_BUILT, with everything else treated (and reported) as :failed.
    # A new status that does not fit these shapes will be reported as a
    # failure at runtime — this test makes the mismatch fail in CI instead.
    let(:ensure_service_block) do
      block = monadic_sh[/^image-status\).*?^ensure-service\)(.*?)^refresh-service\)/m, 1] ||
              monadic_sh[/^ensure-service\)(.*?)^refresh-service\)/m, 1]
      expect(block).not_to be_nil, 'ensure-service case block not found in monadic.sh'
      block
    end

    it 'emits only tokens the Ruby consumer recognizes' do
      tokens = ensure_service_block.scan(/echo "([A-Z][A-Z_]*)"/).flatten.uniq
      expect(tokens).not_to be_empty
      unrecognized = tokens.reject do |t|
        %w[STARTED ALREADY_RUNNING].include?(t) ||
          t.match?(/\A[A-Z]+_DISABLED\z/) ||
          t.match?(/\A[A-Z]+_NOT_BUILT\z/)
      end
      expect(unrecognized).to be_empty,
        "ensure-service emits status tokens container_dependencies.rb would treat as :failed: #{unrecognized}\n" \
        'Either make them fit STARTED/ALREADY_RUNNING/*_DISABLED/*_NOT_BUILT or extend start_service.'
    end

    it 'keeps the consumer-side patterns start_service relies on' do
      expect(container_deps).to include('when "STARTED"')
      expect(container_deps).to include('when "ALREADY_RUNNING"')
      expect(container_deps).to include('_DISABLED')
      expect(container_deps).to include('_NOT_BUILT')
    end
  end

  describe 'image-status contract (consumed by app/main.js queryContainerImageStatus)' do
    it 'producer and consumer agree on the service names' do
      block = monadic_sh[/^image-status\)(.*?)^\s*;;/m, 1]
      expect(block).not_to be_nil, 'image-status case block not found in monadic.sh'
      produced = block.scan(/"([a-z]+)=(?:yohasebe|ghcr\.io)/).flatten.uniq.sort
      expect(produced).to eq(%w[extractor privacy python]),
        "image-status services drifted in monadic.sh: #{produced}"
      produced.each do |name|
        expect(main_js).to include("'#{name}' in status"),
          "main.js queryContainerImageStatus no longer validates the '#{name}' key"
      end
    end

    it 'both sides reference the DOCKER_NOT_RUNNING sentinel' do
      expect(monadic_sh).to include('echo "DOCKER_NOT_RUNNING"')
      expect(main_js).to include("DOCKER_NOT_RUNNING")
    end
  end

  describe 'build lifecycle messages (consumed by app/main.js runCommand)' do
    # Canonical list. Each string must appear in a monadic.sh echo AND in a
    # main.js output.includes(...) handler. Add here when introducing a new
    # build marker; the test then forces wiring up both sides.
    CONTRACT_STRINGS = [
      'Privacy container build succeeded',
      'Privacy container build failed',
      'Extractor container build succeeded',
      'Extractor container build failed',
      'Build of Ruby container has finished',
      'Build of Python container has finished',
      'Build of user containers has finished',
      'Build of Monadic Chat has finished',
      'Container failed to build',
      '[SERVER STARTED]'
    ].freeze

    CONTRACT_STRINGS.each do |str|
      it "'#{str}' is emitted by monadic.sh and handled by main.js" do
        expect(monadic_sh).to include(str),
          "monadic.sh no longer emits #{str.inspect} — update the consumer (and this list) together"
        expect(main_js).to include(str),
          "app/main.js no longer handles #{str.inspect} — the signal is dead"
      end
    end

    it 'REFRESHED (refresh-service) is emitted and consumed' do
      expect(monadic_sh).to include('echo "REFRESHED"')
      expect(main_js).to include("REFRESHED")
    end

    # Documented dead/one-sided signals (intentional, do not "fix"):
    # - refresh-service NOT_RUNNING: normal no-op; main.js only reacts to
    #   REFRESHED and silence is the correct behavior for a stopped container.
    # - "Selenium container built successfully": internal selective-rebuild
    #   path only; no Electron menu invokes build_selenium_container, so the
    #   untranslated passthrough to the console log is acceptable.
    # - [BUILD_COMPLETE] success/failed: consumed by the python build tracker
    #   block in main.js (isBuildPython), covered indirectly by the
    #   '[BUILD_RUN_DIR]' machinery rather than the translation chain.
  end
end
