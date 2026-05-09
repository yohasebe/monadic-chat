# frozen_string_literal: true

require 'json'
require 'monadic/utils/privacy/export_cipher'

RSpec.describe Monadic::Utils::Privacy::ExportCipher do
  let(:passphrase) { 'correct horse battery staple' }
  let(:header) do
    {
      created_at: '2026-04-26T10:00:00Z',
      app_name: 'Mail Composer',
      message_count: 4,
      registry_count: 2
    }
  end
  let(:payload) do
    {
      messages: [
        { role: 'user', text: 'Email John Smith.' },
        { role: 'assistant', text: 'Drafted.' }
      ],
      registry: { '<<PERSON_1>>' => 'John Smith' }
    }
  end

  describe '.encrypt' do
    it 'returns an envelope with the expected schema' do
      env = described_class.encrypt(header: header, plaintext: payload, passphrase: passphrase)
      expect(env['schema_version']).to eq(described_class::SCHEMA_VERSION)
      expect(env['header']).to eq(header)
      expect(env.dig('envelope', 'kdf', 'algorithm')).to eq('argon2id')
      expect(env.dig('envelope', 'cipher', 'algorithm')).to eq('AES-256-GCM')
      expect(env.dig('envelope', 'kdf', 'salt')).to be_a(String)
      expect(env.dig('envelope', 'cipher', 'iv')).to be_a(String)
      expect(env.dig('envelope', 'cipher', 'ciphertext')).to be_a(String)
      expect(env.dig('envelope', 'cipher', 'auth_tag')).to be_a(String)
      expect(env.dig('integrity', 'header_sha256')).to match(/\A[0-9a-f]{64}\z/)
    end

    it 'produces different salt + iv on each call (randomness)' do
      env1 = described_class.encrypt(header: header, plaintext: payload, passphrase: passphrase)
      env2 = described_class.encrypt(header: header, plaintext: payload, passphrase: passphrase)
      expect(env1.dig('envelope', 'kdf', 'salt')).not_to eq(env2.dig('envelope', 'kdf', 'salt'))
      expect(env1.dig('envelope', 'cipher', 'iv')).not_to eq(env2.dig('envelope', 'cipher', 'iv'))
    end

    it 'rejects empty passphrase' do
      expect {
        described_class.encrypt(header: header, plaintext: payload, passphrase: '')
      }.to raise_error(ArgumentError, /passphrase required/)
    end
  end

  describe '.decrypt' do
    let(:envelope) { described_class.encrypt(header: header, plaintext: payload, passphrase: passphrase) }

    it 'recovers the original payload exactly (round-trip)' do
      decrypted = described_class.decrypt(envelope: envelope, passphrase: passphrase)
      # Compare via JSON normalization so symbol vs string keys converge.
      expect(JSON.parse(decrypted)).to eq(JSON.parse(JSON.generate(payload)))
    end

    it 'survives JSON serialization of the envelope (real-world export → import)' do
      json_str = JSON.generate(envelope)
      reloaded = JSON.parse(json_str)
      decrypted = described_class.decrypt(envelope: reloaded, passphrase: passphrase)
      expect(JSON.parse(decrypted)).to eq(JSON.parse(JSON.generate(payload)))
    end

    it 'fails with the wrong passphrase' do
      expect {
        described_class.decrypt(envelope: envelope, passphrase: 'wrong passphrase')
      }.to raise_error(described_class::DecryptionError, /wrong passphrase or corrupted/)
    end

    it 'detects header tampering via SHA-256 mismatch' do
      tampered = JSON.parse(JSON.generate(envelope))
      tampered['header']['app_name'] = 'EvilApp'
      expect {
        described_class.decrypt(envelope: tampered, passphrase: passphrase)
      }.to raise_error(described_class::IntegrityError, /header_sha256 mismatch/)
    end

    it 'detects ciphertext tampering via auth_tag mismatch' do
      tampered = JSON.parse(JSON.generate(envelope))
      ct = tampered['envelope']['cipher']['ciphertext']
      # Flip a bit in the base64 ciphertext
      decoded = Base64.strict_decode64(ct)
      decoded[0] = (decoded[0].ord ^ 0x01).chr
      tampered['envelope']['cipher']['ciphertext'] = Base64.strict_encode64(decoded)
      expect {
        described_class.decrypt(envelope: tampered, passphrase: passphrase)
      }.to raise_error(described_class::DecryptionError)
    end

    it 'rejects empty passphrase' do
      expect {
        described_class.decrypt(envelope: envelope, passphrase: '')
      }.to raise_error(ArgumentError, /passphrase required/)
    end
  end

  describe '.header_digest' do
    it 'is stable across symbol vs string keys' do
      sym = { a: 1, b: { c: 2 } }
      str = { 'a' => 1, 'b' => { 'c' => 2 } }
      expect(described_class.header_digest(sym)).to eq(described_class.header_digest(str))
    end

    it 'is order-independent' do
      a = { x: 1, y: 2 }
      b = { y: 2, x: 1 }
      expect(described_class.header_digest(a)).to eq(described_class.header_digest(b))
    end

    it 'changes when content changes' do
      a = { app: 'mail' }
      b = { app: 'chat' }
      expect(described_class.header_digest(a)).not_to eq(described_class.header_digest(b))
    end
  end
end
