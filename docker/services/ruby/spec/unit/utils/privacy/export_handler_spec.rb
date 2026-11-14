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
  let(:session) do
    { messages: messages, parameters: { 'app_name' => 'MailComposerOpenAI' } }.tap do |chat|
      Monadic::Workspace::Chats.start_new!(chat)
      Monadic::Utils::Privacy::Words.start!(chat).confirm_all!([['John Smith', 'PERSON'], ['john.smith@acme.com', 'EMAIL_ADDRESS']])
    end
  end

  after do
    words = Monadic::Utils::Privacy::Words
    words::LOCK.synchronize { words::TABLES.clear }
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
      f = harness.send(:privacy_export_filename, 'MailComposerOpenAI', true, 'restored')
      expect(f).to match(/MailComposerOpenAI-\d{8}-\d{6}\.mcp-privacy\.json/)
      f = harness.send(:privacy_export_filename, 'MailComposerOpenAI', true, 'masked')
      expect(f).to end_with('.mcp-privacy.json')
      f = harness.send(:privacy_export_filename, 'MailComposerOpenAI', false, 'masked')
      expect(f).to end_with('.masked.json')
      f = harness.send(:privacy_export_filename, 'MailComposerOpenAI', false, 'restored')
      expect(f).to end_with('.plain.json')
    end

    it 'tags plain-restored exports with -PRIVATE so the PII-on-disk variant is visible at a glance' do
      f = harness.send(:privacy_export_filename, 'MailComposerOpenAI', false, 'restored')
      expect(f).to match(/-\d{6}-PRIVATE\.plain\.json\z/)
    end

    it 'does not add the -PRIVATE suffix to other variants' do
      expect(harness.send(:privacy_export_filename, 'MailComposerOpenAI', true, 'restored')).not_to include('-PRIVATE')
      expect(harness.send(:privacy_export_filename, 'MailComposerOpenAI', true, 'masked')).not_to include('-PRIVATE')
      expect(harness.send(:privacy_export_filename, 'MailComposerOpenAI', false, 'masked')).not_to include('-PRIVATE')
    end

    it 'falls back to "monadic" when app_name is missing' do
      f = harness.send(:privacy_export_filename, '', true, 'restored')
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
      expect(parsed['word_table']['schema']).to eq(Monadic::Utils::Privacy::WordTable::SCHEMA)
      expect(parsed['messages'].length).to eq(2)
      expect(parsed['messages'][1]['text']).to include('john.smith@acme.com')
    end

    context 'when a hidden word is also in the app name' do
      let(:session) do
        { messages: messages, parameters: { 'app_name' => 'MailComposerOpenAI' } }.tap do |chat|
          Monadic::Workspace::Chats.start_new!(chat)
          Monadic::Utils::Privacy::Words.start!(chat).confirm_all!([['Composer', 'PERSON']])
        end
      end

      it 'names the app with the word hidden in the plain header and the file name of an encrypted masked file' do
        harness.send(:handle_ws_privacy_export, :conn, session,
                     { 'encrypt' => true, 'content' => 'masked', 'passphrase' => 'correct horse battery staple' })
        payload = harness.sent.last
        expect(payload['type']).to eq('privacy_export_data')
        expect(payload['filename']).not_to include('Composer')
        header = JSON.parse(Base64.strict_decode64(payload['content_base64']))['header']
        expect(header.to_json).not_to include('Composer')
      end

      it 'names the app with the word hidden in the file name of a plain masked file' do
        harness.send(:handle_ws_privacy_export, :conn, session, { 'encrypt' => false, 'content' => 'masked' })
        expect(harness.sent.last['filename']).not_to include('Composer')
      end
    end

    it 'returns masked-only payload without the table' do
      harness.send(:handle_ws_privacy_export, :conn, session, { 'mode' => 'masked_only' })
      payload = harness.sent.last
      expect(payload['mode']).to eq('masked_only')
      content = Base64.strict_decode64(payload['content_base64'])
      parsed = JSON.parse(content)
      expect(parsed).not_to have_key('registry')
      expect(parsed).not_to have_key('word_table')
      expect(parsed['messages'][0]['text']).to eq('Email <<PERSON_1>>.')
      expect(parsed['messages'][1]['text']).to eq('Drafted to <<EMAIL_ADDRESS_1>>.')
    end

    it "masks the names an app keeps its items by in its state, keeping the state's form" do
      session[:monadic_state] = {
        'NovelWriterOpenAI' => {
          novel_context: { data: { 'characters' => { 'John Smith' => { 'role' => 'hero, friend of John Smith' } } },
                           version: 2, updated_at: 'now' }
        }
      }
      harness.send(:handle_ws_privacy_export, :conn, session, { 'mode' => 'masked_only' })
      parsed = JSON.parse(Base64.strict_decode64(harness.sent.last['content_base64']))
      entry = parsed['monadic_state']['NovelWriterOpenAI']['novel_context']
      expect(entry['data']).to eq('characters' => { '<<PERSON_1>>' => { 'role' => 'hero, friend of <<PERSON_1>>' } })
      expect(entry['version']).to eq(2)
    end

    it 'refuses a masked file where two names of an app state would become one' do
      session[:monadic_state] = {
        'NovelWriterOpenAI' => {
          novel_context: { data: { 'characters' => { 'John Smith' => 1, '<<PERSON_1>>' => 2 } } }
        }
      }
      harness.send(:handle_ws_privacy_export, :conn, session, { 'mode' => 'masked_only' })
      expect(harness.sent.last['content_base64']).to be_nil
    end

    it 'returns restored payload with the table attached' do
      harness.send(:handle_ws_privacy_export, :conn, session, { 'mode' => 'restored' })
      payload = harness.sent.last
      expect(payload['mode']).to eq('restored')
      content = Base64.strict_decode64(payload['content_base64'])
      parsed = JSON.parse(content)
      expect(parsed['word_table']['schema']).to eq(Monadic::Utils::Privacy::WordTable::SCHEMA)
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
      # Masked content holds no table in the encrypted payload
      expect(parsed).not_to have_key('word_table')
      expect(parsed).not_to have_key('registry')
      expect(parsed['messages'][0]['text']).to eq('Email <<PERSON_1>>.')
    end

    it 'allows encrypting a chat that hides no words, for at-rest protection' do
      no_privacy_session = {
        messages: [{ 'mid' => 'b1', 'role' => 'user', 'text' => 'Plain trade-secret discussion.' }],
        parameters: { 'app_name' => 'ChatOpenAI' }
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

    it 'plain export of a chat that hides no words holds no table or registry' do
      no_privacy_session = {
        messages: [{ 'mid' => 'c1', 'role' => 'user', 'text' => 'Hi there.' }],
        parameters: { 'app_name' => 'ChatOpenAI' }
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
