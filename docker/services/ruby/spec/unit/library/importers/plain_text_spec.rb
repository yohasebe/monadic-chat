# frozen_string_literal: true

require 'spec_helper'
require 'monadic/library'

RSpec.describe Monadic::Library::Importers::PlainText do
  let(:schema) { Monadic::Library::Schema }

  describe '.can_import?' do
    it 'recognises text with at least one "Speaker: ..." line' do
      input = "Alice: Hello\nBob: Hi\n"
      expect(described_class.can_import?(input)).to be true
    end

    it 'rejects strings with no speaker headers' do
      input = "Just plain prose.\nNo colons in front."
      expect(described_class.can_import?(input)).to be false
    end

    it 'rejects non-string input' do
      expect(described_class.can_import?(['Alice: Hello'])).to be false
    end
  end

  describe '.import' do
    let(:input) do
      <<~TEXT
        Alice: Hello, Bob.
        Bob: Hi Alice. How are you?
        Alice: Doing well.
          Just got back from a trip.
        Bob: That's great.
      TEXT
    end

    it 'produces a valid v1 conversation' do
      result = described_class.import(input, license: 'CC-BY-4.0')
      expect(schema.valid?(result)).to be true
    end

    it 'creates one participant per unique speaker label' do
      result = described_class.import(input)
      labels = result['participants'].map { |p| p['label'] }
      expect(labels).to contain_exactly('Alice', 'Bob')
      expect(result['participants'].map { |p| p['role'] }).to all(eq('human'))
    end

    it 'preserves speech order' do
      result = described_class.import(input)
      pid_alice = result['participants'].find { |p| p['label'] == 'Alice' }['id']
      pid_bob = result['participants'].find { |p| p['label'] == 'Bob' }['id']
      sequence = result['messages'].map { |m| m['speaker']['id'] }
      expect(sequence).to eq([pid_alice, pid_bob, pid_alice, pid_bob])
    end

    it 'merges continuation lines into the preceding turn' do
      result = described_class.import(input)
      alice_second = result['messages'][2]
      expect(alice_second['text']).to eq("Doing well.\nJust got back from a trip.")
    end

    it 'allows overriding default_role for monologue corpora' do
      mono = "Speaker A: First sentence.\nSpeaker A: Second sentence."
      result = described_class.import(mono, default_role: 'narrator')
      expect(result['participants'].first['role']).to eq('narrator')
    end

    it 'raises when the input has no speaker-labeled lines' do
      expect {
        described_class.import("Just text\nNothing labeled")
      }.to raise_error(ArgumentError, /No speaker-labeled lines/)
    end
  end
end
