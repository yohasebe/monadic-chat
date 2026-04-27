# frozen_string_literal: true

require 'json'
require 'monadic/utils/privacy/export_cipher'

# We exercise the WebSocketHelper privacy export helpers without booting the
# full WebSocket stack: include the module into a tiny harness and stub
# send_to_client to capture outgoing messages.

require_relative '../../../../lib/monadic/utils/websocket/privacy_handler'

RSpec.describe 'WebSocketHelper privacy export (block D.2)' do
  let(:harness_class) do
    Class.new do
      include WebSocketHelper
      attr_reader :sent

      def initialize
        @sent = []
      end

      def send_to_client(_connection, payload)
        @sent << payload
      end
    end
  end

  let(:harness) { harness_class.new }
  let(:registry) do
    {
      '<<PERSON_1>>' => 'John Smith',
      '<<EMAIL_ADDRESS_1>>' => 'john.smith@acme.com'
    }
  end
  let(:messages) do
    [
      { 'mid' => 'a1', 'role' => 'user', 'text' => 'Email John Smith.', 'app_name' => 'MailComposerOpenAI' },
      { 'mid' => 'a2', 'role' => 'assistant', 'text' => 'Drafted to john.smith@acme.com.', 'app_name' => 'MailComposerOpenAI' }
    ]
  end
  let(:pipeline) do
    Class.new do
      def initialize(reg); @state = { registry: reg }; end
      def registry_state; @state; end
    end.new(registry)
  end
  let(:session) do
    { messages: messages, parameters: { 'app_name' => 'MailComposerOpenAI' }, _privacy_pipeline: pipeline }
  end

  describe 'privacy_remask_messages' do
    it 'replaces longer values first to avoid partial matches' do
      result = harness.send(:privacy_remask_messages, messages, registry)
      expect(result[0]['text']).to eq('Email <<PERSON_1>>.')
      expect(result[1]['text']).to eq('Drafted to <<EMAIL_ADDRESS_1>>.')
    end

    it 'is a no-op when registry is empty' do
      result = harness.send(:privacy_remask_messages, messages, {})
      expect(result).to eq(messages)
    end
  end

  describe 'privacy_export_filename' do
    it 'sanitizes app_name and picks an extension matching the (encrypt, content) axes' do
      f = harness.send(:privacy_export_filename, session, true, 'restored')
      expect(f).to match(/MailComposerOpenAI-\d{8}-\d{6}\.mcp-privacy\.json/)
      f = harness.send(:privacy_export_filename, session, true, 'masked')
      expect(f).to end_with('.mcp-privacy.json')
      f = harness.send(:privacy_export_filename, session, false, 'masked')
      expect(f).to end_with('.masked.json')
      f = harness.send(:privacy_export_filename, session, false, 'restored')
      expect(f).to end_with('.plain.json')
    end

    it 'falls back to "monadic" when app_name is missing' do
      bare_session = { parameters: {} }
      f = harness.send(:privacy_export_filename, bare_session, true, 'restored')
      expect(f).to start_with('monadic-')
    end
  end

  describe 'privacy_export_params (legacy mode translation)' do
    it 'maps legacy mode "encrypted" to (encrypt: true, content: "restored")' do
      expect(harness.send(:privacy_export_params, { 'mode' => 'encrypted' })).to eq([true, 'restored'])
    end

    it 'maps legacy mode "masked_only" to (encrypt: false, content: "masked")' do
      expect(harness.send(:privacy_export_params, { 'mode' => 'masked_only' })).to eq([false, 'masked'])
    end

    it 'maps legacy mode "restored" to (encrypt: false, content: "restored")' do
      expect(harness.send(:privacy_export_params, { 'mode' => 'restored' })).to eq([false, 'restored'])
    end

    it 'falls back to plain restored when both legacy and new params are absent' do
      expect(harness.send(:privacy_export_params, {})).to eq([false, 'restored'])
    end

    it 'prefers the new 2-axis form over legacy mode when both are present' do
      obj = { 'encrypt' => true, 'content' => 'masked', 'mode' => 'restored' }
      expect(harness.send(:privacy_export_params, obj)).to eq([true, 'masked'])
    end
  end

  describe 'handle_ws_privacy_export' do
    it 'rejects unknown content kinds' do
      harness.send(:handle_ws_privacy_export, :conn, session,
                   { 'encrypt' => false, 'content' => 'leaky' })
      expect(harness.sent.last['type']).to eq('privacy_export_error')
      expect(harness.sent.last['error']).to eq('invalid_content')
    end

    it 'rejects encrypted mode without passphrase' do
      harness.send(:handle_ws_privacy_export, :conn, session, { 'mode' => 'encrypted', 'passphrase' => '' })
      expect(harness.sent.last['type']).to eq('privacy_export_error')
      expect(harness.sent.last['error']).to eq('passphrase_required')
    end

    it 'returns a downloadable encrypted blob and round-trips through ExportCipher' do
      harness.send(:handle_ws_privacy_export, :conn, session,
                   { 'mode' => 'encrypted', 'passphrase' => 'correct horse battery staple' })
      payload = harness.sent.last
      expect(payload['type']).to eq('privacy_export_data')
      expect(payload['mode']).to eq('encrypted')
      expect(payload['filename']).to end_with('.mcp-privacy.json')

      content = Base64.strict_decode64(payload['content_base64'])
      envelope = JSON.parse(content)
      expect(envelope['header']['app_name']).to eq('MailComposerOpenAI')
      expect(envelope['header']['message_count']).to eq(2)

      decrypted = Monadic::Utils::Privacy::ExportCipher.decrypt(
        envelope: envelope, passphrase: 'correct horse battery staple'
      )
      parsed = JSON.parse(decrypted)
      expect(parsed['registry']).to eq(registry)
      expect(parsed['messages'].length).to eq(2)
      expect(parsed['messages'][1]['text']).to include('john.smith@acme.com')
    end

    it 'returns masked-only payload without registry exposure' do
      harness.send(:handle_ws_privacy_export, :conn, session, { 'mode' => 'masked_only' })
      payload = harness.sent.last
      expect(payload['mode']).to eq('masked_only')
      content = Base64.strict_decode64(payload['content_base64'])
      parsed = JSON.parse(content)
      expect(parsed).not_to have_key('registry')
      expect(parsed['messages'][0]['text']).to eq('Email <<PERSON_1>>.')
      expect(parsed['messages'][1]['text']).to eq('Drafted to <<EMAIL_ADDRESS_1>>.')
    end

    it 'returns restored payload with registry attached' do
      harness.send(:handle_ws_privacy_export, :conn, session, { 'mode' => 'restored' })
      payload = harness.sent.last
      expect(payload['mode']).to eq('restored')
      content = Base64.strict_decode64(payload['content_base64'])
      parsed = JSON.parse(content)
      expect(parsed['registry']).to eq(registry)
      expect(parsed['messages'][0]['text']).to eq('Email John Smith.')
    end

    it 'supports encrypted + masked content (axes can be combined freely)' do
      harness.send(:handle_ws_privacy_export, :conn, session,
                   { 'encrypt' => true, 'content' => 'masked', 'passphrase' => 'a-strong-passphrase-12345' })
      payload = harness.sent.last
      expect(payload['type']).to eq('privacy_export_data')
      expect(payload['mode']).to eq('encrypted_masked')
      expect(payload['encrypt']).to be true
      expect(payload['content']).to eq('masked')
      expect(payload['filename']).to end_with('.mcp-privacy.json')

      content = Base64.strict_decode64(payload['content_base64'])
      envelope = JSON.parse(content)
      decrypted = Monadic::Utils::Privacy::ExportCipher.decrypt(
        envelope: envelope, passphrase: 'a-strong-passphrase-12345'
      )
      parsed = JSON.parse(decrypted)
      # Masked content drops the registry from the encrypted payload
      expect(parsed['registry']).to eq({})
      expect(parsed['messages'][0]['text']).to eq('Email <<PERSON_1>>.')
    end

    it 'allows encrypting a non-privacy session (registry empty) for at-rest protection' do
      no_privacy_session = {
        messages: [{ 'mid' => 'b1', 'role' => 'user', 'text' => 'Plain trade-secret discussion.' }],
        parameters: { 'app_name' => 'ChatOpenAI' },
        _privacy_pipeline: nil
      }
      harness.send(:handle_ws_privacy_export, :conn, no_privacy_session,
                   { 'encrypt' => true, 'content' => 'restored', 'passphrase' => 'a-strong-passphrase-12345' })
      payload = harness.sent.last
      expect(payload['type']).to eq('privacy_export_data')
      expect(payload['encrypt']).to be true

      envelope = JSON.parse(Base64.strict_decode64(payload['content_base64']))
      decrypted = Monadic::Utils::Privacy::ExportCipher.decrypt(
        envelope: envelope, passphrase: 'a-strong-passphrase-12345'
      )
      parsed = JSON.parse(decrypted)
      expect(parsed['messages'][0]['text']).to eq('Plain trade-secret discussion.')
    end

    it 'plain export of non-privacy session omits the empty registry from output' do
      no_privacy_session = {
        messages: [{ 'mid' => 'c1', 'role' => 'user', 'text' => 'Hi there.' }],
        parameters: { 'app_name' => 'ChatOpenAI' },
        _privacy_pipeline: nil
      }
      harness.send(:handle_ws_privacy_export, :conn, no_privacy_session,
                   { 'encrypt' => false, 'content' => 'restored' })
      payload = harness.sent.last
      parsed = JSON.parse(Base64.strict_decode64(payload['content_base64']))
      expect(parsed).not_to have_key('registry')
      expect(parsed['messages'][0]['text']).to eq('Hi there.')
    end
  end
end
