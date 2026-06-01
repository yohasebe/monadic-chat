# frozen_string_literal: true

# Privacy golden-fixture safety net (Substitution Pipeline Phase 2.1).
#
# Each fixture replays a recorded (or authored) Presidio response through the
# real Privacy::Pipeline and asserts the full set of observable Ruby outputs
# (masking, restore round-trip, restored spans, missing placeholders, TTS
# labels, registry, registry entries). This pins the behaviour that the Phase
# 2.2 refactor (moving privacy onto the Substitution provider abstraction) must
# preserve. Regenerate with: bundle exec ruby spec/golden/privacy/capture.rb
#
# These are container-free and deterministic: tokens live in canonical
# notation, languages are fixed per fixture, and the backend is stubbed.

require_relative 'support'

RSpec.describe 'Privacy golden fixtures' do
  fixtures = YAML.safe_load_file(File.expand_path('fixtures.yml', __dir__))

  it 'loads a non-empty fixture set' do
    expect(fixtures).to be_a(Array)
    expect(fixtures.length).to be >= 20
  end

  it 'has unique fixture ids' do
    ids = fixtures.map { |f| f['id'] }
    expect(ids).to eq(ids.uniq)
  end

  fixtures.each do |fixture|
    describe fixture['id'] do
      it "preserves recorded behaviour: #{fixture['description']}" do
        responses = (fixture['backend'] || []).map { |r| PrivacyGolden::Cassette.to_backend_response(r) }
        backend = PrivacyGolden::StubBackend.new(responses)
        actual = PrivacyGolden::Harness.run(fixture, backend)
        expect(actual).to eq(fixture['golden'])
      end
    end
  end
end

# Drift guard: the golden harness renders canonical tokens to a *wire* form via
# PrivacyGolden::Format. That wire form must stay in lockstep with the
# production placeholder regexes, otherwise the golden would silently validate
# the wrong format. When Phase 2.2 migrates the wire form (e.g. to ${TYPE_N}),
# updating Format::WIRE_* and the production regexes together keeps this green.
RSpec.describe 'Privacy placeholder format lockstep' do
  let(:sample) { PrivacyGolden::Format.render('PERSON', 1) }

  it 'golden renderer produces the current wire form' do
    expect(sample).to eq('<<PERSON_1>>')
  end

  it 'matches Pipeline::TTS_PLACEHOLDER_RE with correct captures' do
    m = sample.match(Monadic::Utils::Privacy::Pipeline::TTS_PLACEHOLDER_RE)
    expect(m).not_to be_nil
    expect([m[1], m[2]]).to eq(['PERSON', '1'])
  end

  it 'matches StreamingRestorer::PLACEHOLDER_RE' do
    expect(sample).to match(Monadic::Utils::Privacy::StreamingRestorer::PLACEHOLDER_RE)
  end

  it 'round-trips through canonical/wire translation' do
    expect(PrivacyGolden::Format.to_canon(sample)).to eq('{{PERSON_1}}')
    expect(PrivacyGolden::Format.to_wire('{{PERSON_1}}')).to eq(sample)
  end

  it 'matches a multi-segment entity type (EMAIL_ADDRESS)' do
    wire = PrivacyGolden::Format.render('EMAIL_ADDRESS', 2)
    m = wire.match(Monadic::Utils::Privacy::Pipeline::TTS_PLACEHOLDER_RE)
    expect([m[1], m[2]]).to eq(['EMAIL_ADDRESS', '2'])
  end

  # Cross-language guard: the Python Presidio container generates the wire form
  # independently (docker/services/privacy/server.py). Keep the two in sync.
  # Skipped when the Python source is absent (packaged / headless runs).
  it 'agrees with the Python container placeholder format' do
    server_py = File.expand_path('../../../../privacy/server.py', __dir__)
    skip "Python source not present at #{server_py}" unless File.exist?(server_py)
    source = File.read(server_py)
    # server.py builds tokens with an f-string ( f"<<{...}_{...}>>" ) and parses
    # them with a compiled regex. Assert both still use the << / >> delimiters.
    expect(source).to include('f"<<'), 'server.py no longer builds tokens with the << prefix'
    expect(source).to include('>>"'), 'server.py no longer builds tokens with the >> suffix'
  end
end
