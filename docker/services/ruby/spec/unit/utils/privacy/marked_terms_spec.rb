# frozen_string_literal: true

require 'spec_helper'
require 'base64'
require 'json'
require 'open3'
require 'rbconfig'
require 'tmpdir'
require 'rack'
require 'rack/session/pool'
require_relative '../../../../lib/monadic/utils/unlimited_session_store'
require_relative '../../../../lib/monadic/utils/privacy/marks'
require_relative '../../../../lib/monadic/utils/privacy/registry'
require_relative '../../../../lib/monadic/utils/privacy/outbound'
require_relative '../../../../lib/monadic/utils/privacy/presidio_backend'
require_relative '../../../../lib/monadic/utils/privacy/pipeline'
require_relative '../../../../lib/monadic/utils/privacy/types'
require_relative '../../../../lib/monadic/adapters/base_vendor_helper'
require_relative '../../../../lib/monadic/utils/websocket'
require_relative '../../../../lib/monadic/agents/context_extractor_agent'
require_relative '../../../../lib/monadic/adapters/vendors/gemini_helper'
require_relative '../../../../lib/monadic/agents/ai_user_agent'
require_relative '../../../../lib/monadic/adapters/vendors/openai_helper'

# Words the user marks for the Privacy Filter (⟦…⟧): taken out of what they
# write, kept for the chat, masked wherever they occur, and never sent
# unmasked (filter off, an old container, a failed detection, a message the
# masking did not reach).
RSpec.describe 'Words the user marks for the Privacy Filter' do
  let(:marks) { Monadic::Utils::Privacy::Marks }

  def real_session(values)
    made = nil
    inner = lambda do |env|
      made = env['rack.session']
      values.each { |k, v| made[k] = v }
      [200, {}, ['ok']]
    end
    Rack::Session::CappedPool.new(inner, key: 'monadic.session').call(Rack::MockRequest.env_for('/'))
    made
  end

  describe 'reading the marks' do
    it 'takes them out and keeps the words, with their types' do
      text, terms = marks.extract('僕は⟦江戸川今太郎⟧です。⟦Acme社|組織⟧と⟦Paris|place⟧へ。⟦江戸川今太郎⟧')
      expect(text).to eq('僕は江戸川今太郎です。Acme社とParisへ。江戸川今太郎')
      expect(terms).to contain_exactly({ text: '江戸川今太郎', type: 'PERSON' }, { text: 'Acme社', type: 'ORGANIZATION' },
                                       { text: 'Paris', type: 'LOCATION' })
    end

    it 'leaves text with no marks as it is' do
      expect(marks.extract('a | b [c]')).to eq(['a | b [c]', []])
    end

    it 'reads \\⟦ and \\⟧ as the brackets themselves' do
      expect(marks.extract('x \\⟦not\\⟧ y')).to eq(['x ⟦not⟧ y', []])
    end

    it 'refuses a mark it cannot read, without repeating the word' do
      ['⟦open', 'close⟧', '⟦a⟦b⟧⟧', '⟦⟧', "⟦a\nb⟧", '⟦x|nickname⟧', "⟦#{'x' * 201}⟧"].each do |bad|
        expect { marks.extract(bad) }.to raise_error(marks::Invalid) { |e| expect(e.message).not_to include('nickname') }
      end
    end
  end

  describe 'the chat keeping the words' do
    it 'keeps each word once, with the type it was marked with last, and forgets them on reset' do
      registry = Monadic::Utils::Privacy::Registry.new({})
      registry.add_terms!([{ text: 'Acme', type: 'PERSON' }])
      registry.add_terms!([{ text: 'Acme', type: 'ORGANIZATION' }, { text: 'Bob', type: 'PERSON' }])
      expect(registry.terms).to eq([{ text: 'Acme', type: 'ORGANIZATION' }, { text: 'Bob', type: 'PERSON' }])
      registry.reset!
      expect(registry.terms).to eq([])
    end
  end

  describe 'the Privacy container' do
    let(:backend) { Monadic::Utils::Privacy::PresidioBackend.new(endpoint: 'http://privacy.invalid') }

    it 'is not sent the words when it does not mask them, and nothing is sent' do
      allow(backend).to receive(:supports_terms?).and_return(false)
      expect(backend).not_to receive(:post_json)
      expect do
        backend.anonymize(text: 'Bob', languages: ['en'], registry: {}, terms: [{ text: 'Bob', type: 'PERSON' }])
      end.to raise_error(Monadic::Utils::Privacy::BackendError, /update/)
    end

    it 'is sent the words when it masks them' do
      allow(backend).to receive(:supports_terms?).and_return(true)
      expect(backend).to receive(:post_json).with('/v1/anonymize', hash_including(terms: [{ text: 'Bob', type: 'PERSON' }]))
                                            .and_return('masked_text' => '<<PERSON_1>>', 'registry' => {})
      backend.anonymize(text: 'Bob', languages: ['en'], registry: {}, terms: [{ text: 'Bob', type: 'PERSON' }])
    end

    it 'gives no masked text: nothing is sent' do
      allow(backend).to receive(:post_json).and_return({})
      expect { backend.anonymize(text: 'x', languages: ['en'], registry: {}) }
        .to raise_error(Monadic::Utils::Privacy::BackendError)
    end
  end

  describe 'the masking pipeline' do
    let(:session) { { monadic_state: { privacy: { registry: {}, audit: [], terms: [{ text: 'Bob', type: 'PERSON' }] } } } }

    it 'passes the words with every text it masks' do
      backend = double('Backend')
      expect(backend).to receive(:anonymize).with(hash_including(terms: [{ text: 'Bob', type: 'PERSON' }]))
                                            .and_return(masked_text: '<<PERSON_1>>', registry: {}, entities: [], stats: {})
      pipeline = Monadic::Utils::Privacy::Pipeline.new(backend: backend, config: { enabled: true }, session: session)
      pipeline.before_send_to_llm(Monadic::Utils::Privacy::RawMessage.new('Bob', 'user', {}))
    end

    it 'does not let a failed detection pass the text on when words are marked' do
      backend = double('Backend')
      allow(backend).to receive(:anonymize).and_raise(Monadic::Utils::Privacy::BackendError, 'down')
      pipeline = Monadic::Utils::Privacy::Pipeline.new(backend: backend, config: { enabled: true, on_failure: :pass },
                                                       session: session)
      expect { pipeline.before_send_to_llm(Monadic::Utils::Privacy::RawMessage.new('Bob', 'user', {})) }
        .to raise_error(Monadic::Utils::Privacy::BackendError)
    end

    it 'does not read the words out, even before the model has seen them' do
      pipeline = Monadic::Utils::Privacy::Pipeline.new(backend: double('Backend'), config: { enabled: true }, session: session)
      expect(pipeline.sanitize_restored_for_tts('Dear Bob, thanks')).to eq('Dear PERSON, thanks')
    end
  end

  describe 'what is sent to a model' do
    let(:helper) { Class.new { include BaseVendorHelper }.new }
    let(:session) { { _privacy_session_enabled: true, monadic_state: { privacy: { registry: {}, audit: [], terms: [{ text: 'Bob', type: 'PERSON' }] } } } }
    # A pipeline that masks Bob and keeps it in its registry, as the real one
    # does with a marked word.
    let(:pipeline) do
      registry = {}
      double('Pipeline', registry_state: { registry: registry }).tap do |p|
        allow(p).to receive(:before_send_to_llm) do |raw|
          registry['<<PERSON_1>>'] = 'Bob' if raw.text.include?('Bob')
          double('Masked', text: raw.text.gsub('Bob', '<<PERSON_1>>'))
        end
      end
    end

    it 'masks the messages, and the whole body puts the placeholder in app and tool text too' do
      allow(helper).to receive(:privacy_pipeline_for).and_return(pipeline)
      messages = helper.apply_privacy_to_messages(
        [{ 'role' => 'system', 'content' => 'You help people.' }, { 'role' => 'tool', 'content' => 'Bob wrote back' },
         { 'role' => 'user', 'content' => 'Ask Bob' }], session, { privacy: { enabled: true } }
      )
      body = helper.protect_marked_words!({ 'messages' => messages }, session, {})
      expect(body['messages'].map { |m| m['content'] }).to eq(['You help people.', '<<PERSON_1>> wrote back', 'Ask <<PERSON_1>>'])
    end

    it 'is refused when a marked word has no placeholder to take its place' do
      blind = double('Pipeline', registry_state: { registry: {} })
      allow(blind).to receive(:before_send_to_llm) { |raw| double('Masked', text: raw.text) }
      allow(helper).to receive(:privacy_pipeline_for).and_return(blind)
      expect { helper.protect_marked_words!({ 'messages' => [{ 'role' => 'tool', 'content' => 'Bob' }] }, session, {}) }
        .to raise_error(Monadic::Utils::Privacy::Outbound::Refused)
    end

    it 'is refused when the filter is off but words were marked (the messages step)' do
      allow(helper).to receive(:privacy_pipeline_for).and_return(nil)
      expect { helper.apply_privacy_to_messages([{ 'role' => 'user', 'content' => 'hi' }], session, {}) }
        .to raise_error(Monadic::Utils::Privacy::Outbound::Refused)
    end


    it 'is refused for the helpers that send on the chat’s behalf when the filter is off' do
      off = real_session(parameters: {}, monadic_state: { privacy: { terms: [{ text: 'Bob', type: 'PERSON' }] } })
      expect { Monadic::Utils::Privacy::Outbound.pipeline!(off) }.to raise_error(Monadic::Utils::Privacy::Outbound::Refused)
    end
  end

  # Where a person's text enters the chat: a message sent, a message edited.
  describe 'taking the marks where the chat receives them' do
    let(:host) do
      Class.new { include WebSocketHelper }.new.tap do |h|
        allow(h).to receive(:send_or_broadcast)
        allow(h).to receive(:sync_session_state!)
      end
    end
    let(:privacy_app) { double('App', settings: { privacy: { enabled: true } }) }

    before { stub_const('APPS', { 'MailComposerOpenAI' => privacy_app }) }

    it 'keeps the words and gives the text without the marks when the filter is on' do
      session = real_session(parameters: { 'app_name' => 'MailComposerOpenAI' }, _privacy_session_enabled: true)
      expect(host.take_privacy_marks('僕は⟦江戸川今太郎⟧です', session, 'tab')).to eq('僕は江戸川今太郎です')
      expect(Monadic::Utils::Privacy::Registry.new(session).terms).to eq([{ text: '江戸川今太郎', type: 'PERSON' }])
    end

    it 'refuses marks, and messages after marks, when the filter is off' do
      errors = []
      allow(host).to receive(:send_error) { |msg, _| errors << msg }
      session = real_session(parameters: { 'app_name' => 'MailComposerOpenAI' })
      expect(host.take_privacy_marks('⟦Bob⟧', session, 'tab')).to be_nil

      session[:monadic_state] = { privacy: { terms: [{ text: 'Bob', type: 'PERSON' }] } }
      expect(host.take_privacy_marks('plain text', session, 'tab')).to be_nil
      expect(errors.size).to eq(2)
      expect(errors.join).not_to include('Bob')
    end

    it 'says a refusal was not accepted, so the page keeps the cards it shows' do
      extras = []
      allow(host).to receive(:send_error) { |_msg, _id, extra = {}| extras << extra }
      off = real_session(parameters: { 'app_name' => 'MailComposerOpenAI' })
      host.take_privacy_marks('⟦Bob⟧', off, 'tab')
      on = real_session(parameters: { 'app_name' => 'MailComposerOpenAI' }, _privacy_session_enabled: true)
      host.take_privacy_marks('⟦Bob', on, 'tab')
      expect(extras.size).to eq(2)
      expect(extras).to all(eq('not_accepted' => true))
    end

    it 'takes the marks of a sample message too, and adds nothing when they are refused' do
      allow(host).to receive(:send_error)
      allow(host).to receive(:get_session_params).and_return({ 'app_name' => 'MailComposerOpenAI' })
      on = real_session(parameters: { 'app_name' => 'MailComposerOpenAI' }, _privacy_session_enabled: true, messages: [])
      host.send(:handle_ws_sample, nil, { 'content' => 'I am ⟦Bob⟧', 'role' => 'assistant' }, on)
      expect(on[:messages].map { |m| m['text'] }).to eq(['I am Bob'])
      expect(Monadic::Utils::Privacy::Registry.new(on).terms).to eq([{ text: 'Bob', type: 'PERSON' }])

      off = real_session(parameters: { 'app_name' => 'MailComposerOpenAI' }, messages: [])
      host.send(:handle_ws_sample, nil, { 'content' => 'I am ⟦Bob⟧', 'role' => 'user' }, off)
      expect(off[:messages]).to be_empty
    end

    it 'does not record or send a message whose marks are refused' do
      allow(host).to receive(:send_error)
      session = real_session(parameters: { 'app_name' => 'MailComposerOpenAI' }, messages: [])
      expect(host.send(:handle_ws_streaming, nil, { 'message' => '⟦Bob⟧ hi' }, session, Queue.new)).to be_nil
      expect(session[:messages]).to be_empty
      expect(session[:parameters]).not_to have_key('message')
    end

    it 'refuses words to mask in a system sample or a system edit, which are sent unmasked' do
      errors = []
      allow(host).to receive(:send_error) { |msg, _id, extra = {}| errors << extra.merge('message' => msg) }
      allow(host).to receive(:get_session_params).and_return({ 'app_name' => 'MailComposerOpenAI' })
      session = real_session(parameters: { 'app_name' => 'MailComposerOpenAI' }, _privacy_session_enabled: true,
                             messages: [{ 'mid' => 's1', 'role' => 'system', 'text' => 'Be brief.' }])
      host.send(:handle_ws_sample, nil, { 'content' => 'Call me ⟦Bob⟧', 'role' => 'system' }, session)
      expect(Monadic::Utils::Privacy::Registry.new(session).terms).to be_empty

      Monadic::Utils::Privacy::Registry.new(session).add_terms!([{ text: 'Alice', type: 'PERSON' }])
      host.send(:handle_ws_sample, nil, { 'content' => 'Call me Alice', 'role' => 'system' }, session)
      Thread.current[:rack_session] = session
      host.handle_edit_message(nil, { 'mid' => 's1', 'content' => 'Call me Alice' })
      host.handle_edit_message(nil, { 'mid' => 's1', 'content' => 'Call me ⟦Bob⟧' })

      expect(session[:messages].map { |m| m['text'] }).to eq(['Be brief.'])
      expect(Monadic::Utils::Privacy::Registry.new(session).terms.map { |t| t[:text] }).to eq(['Alice'])
      expect(errors.size).to eq(4)
      expect(errors).to all(include('not_accepted' => true, 'message' => a_string_including('system message')))
      expect(errors.last).to include('edit_refused' => true, 'mid' => 's1')

      host.send(:handle_ws_sample, nil, { 'content' => 'I am ⟦Bob⟧', 'role' => 'user' }, session)
      expect(session[:messages].last['text']).to eq('I am Bob')
    ensure
      Thread.current[:rack_session] = nil
    end

    it 'keeps an edited message as it was when its marks are refused' do
      allow(host).to receive(:send_error)
      session = real_session(parameters: { 'app_name' => 'MailComposerOpenAI' },
                             messages: [{ 'mid' => 'm1', 'role' => 'user', 'text' => 'old' }])
      Thread.current[:rack_session] = session
      extras = []
      allow(host).to receive(:send_error) { |_msg, _id, extra = {}| extras << extra }
      host.handle_edit_message(nil, { 'mid' => 'm1', 'content' => '⟦Bob⟧' })
      expect(session[:messages].first['text']).to eq('old')
      expect(extras).to eq([{ 'not_accepted' => true, 'edit_refused' => true, 'mid' => 'm1' }])
    ensure
      Thread.current[:rack_session] = nil
    end
  end

  describe 'writing the chat to a file' do
    let(:harness) do
      Class.new do
        include WebSocketHelper
        attr_reader :sent

        def initialize
          @sent = []
        end

        def send_to_client(_connection, payload)
          @sent << payload
        end
      end.new
    end
    # No pipeline built (a tab that reconnected): the chat's own state is used.
    let(:session) do
      { messages: [{ 'mid' => 'a', 'role' => 'user', 'text' => '江戸川今太郎です。Bob へ', 'app_name' => 'MailComposerOpenAI' }],
        parameters: { 'app_name' => 'MailComposerOpenAI' },
        monadic_state: { privacy: { registry: { '<<PERSON_1>>' => 'Bob' }, audit: [],
                                    terms: [{ text: '江戸川今太郎', type: 'PERSON' }] } } }
    end

    def export(content)
      harness.send(:handle_ws_privacy_export, nil, session, { 'encrypt' => false, 'content' => content })
      JSON.parse(Base64.strict_decode64(harness.sent.last['content_base64']))
    end

    it 'keeps the marked words in a restored file' do
      file = export('restored')
      expect(file['terms']).to eq([{ 'text' => '江戸川今太郎', 'type' => 'PERSON' }])
      expect(file['messages'].first['text']).to eq('江戸川今太郎です。Bob へ')
    end

    it 'masks the marked words in a masked file, and holds none of them' do
      file = export('masked')
      expect(file).not_to have_key('terms')
      expect(file).not_to have_key('registry')
      expect(file['messages'].first['text']).to eq('<<PERSON_2>>です。<<PERSON_1>> へ')
      expect(JSON.generate(file)).not_to include('江戸川今太郎')
    end
  end

  # The /load route of the app with a file that carries marked words.
  describe 'reading a file back' do
    def probe(terms)
      script = <<~'RUBY'
        require "rack"
        require "rack/mock_request"
        require "json"
        app, = Rack::Builder.parse_file("config.ru")
        conversation = { "parameters" => { "app_name" => "ChatOpenAI" }, "messages" => [{ "role" => "user", "text" => "hi" }],
                         "terms" => JSON.parse(ENV.fetch("PROBE_TERMS")) }.to_json
        body = "--B\r\nContent-Disposition: form-data; name=\"file\"; filename=\"c.json\"\r\n" \
               "Content-Type: application/json\r\n\r\n#{conversation}\r\n" \
               "--B\r\nContent-Disposition: form-data; name=\"tab_id\"\r\n\r\ntab-t\r\n--B--\r\n"
        res = Rack::MockRequest.new(app).post("http://localhost:4567/load", input: body,
                                              "CONTENT_TYPE" => "multipart/form-data; boundary=B", "HTTP_HOST" => "localhost:4567")
        out = JSON.parse(res.body)
        staged = out["import_token"] && WebSocketHelper.take_import("tab-t", out["import_token"])
        puts JSON.generate("response" => out, "terms" => staged && staged.dig(:monadic_state, :privacy, :terms),
                           "enabled" => staged && staged[:_privacy_session_enabled])
      RUBY
      root = File.expand_path('../../../..', __dir__)
      Dir.mktmpdir('terms-load') do |home|
        env = { 'HOME' => home, 'PROBE_TERMS' => JSON.generate(terms) }
        stdout, stderr, status = Open3.capture3(env, RbConfig.ruby, '-e', script, chdir: root)
        raise "probe failed: #{stderr.lines.last(15).join}" unless status.success?

        JSON.parse(stdout.lines.last)
      end
    end

    it 'brings the marked words back, with the Privacy Filter on' do
      out = probe([{ 'text' => '江戸川今太郎', 'type' => 'PERSON' }])
      expect(out['terms']).to eq([{ 'text' => '江戸川今太郎', 'type' => 'PERSON' }])
      expect(out['enabled']).to be true
    end

    it 'stops on marked words it cannot read' do
      out = probe([{ 'text' => 'x', 'type' => 'NICKNAME' }])
      expect(out['response']['success']).to be false
    end
  end

  # The whole request body, speech-to-speech, the masked file, overlapping
  # words, marks in an imported file, the number of words.
  describe 'the whole request body' do
    let(:helper) { Class.new { include BaseVendorHelper }.new }
    let(:session) { { _privacy_session_enabled: true, monadic_state: { privacy: { registry: {}, audit: [], terms: [{ text: 'Bob', type: 'PERSON' }] } } } }
    # A pipeline that masks Bob and keeps it in its registry, as the real one
    # does with a marked word.
    let(:pipeline) do
      registry = {}
      double('Pipeline', registry_state: { registry: registry }).tap do |p|
        allow(p).to receive(:before_send_to_llm) do |raw|
          registry['<<PERSON_1>>'] = 'Bob' if raw.text.include?('Bob')
          double('Masked', text: raw.text.gsub('Bob', '<<PERSON_1>>'))
        end
      end
    end

    it 'masks tool results with the messages' do
      allow(helper).to receive(:privacy_pipeline_for).and_return(pipeline)
      masked = helper.apply_privacy_to_messages(
        [{ 'type' => 'function_call_output', 'call_id' => 'c1', 'output' => 'Bob replied' },
         { 'role' => 'tool', 'content' => 'Bob wrote' },
         { 'role' => 'user', 'content' => [{ 'type' => 'tool_result', 'content' => 'from Bob' },
                                            { 'type' => 'tool_result', 'content' => [{ 'type' => 'text', 'text' => 'Bob' }] }] }],
        session, { privacy: { enabled: true } }
      )
      expect(masked[0]['output']).to eq('<<PERSON_1>> replied')
      expect(masked[1]['content']).to eq('<<PERSON_1>> wrote')
      expect(masked[2]['content'][0]['content']).to eq('from <<PERSON_1>>')
      expect(masked[2].keys).to eq(%w[role content])
      expect(masked[2]['content'][1]['content'][0]['text']).to eq('<<PERSON_1>>')
      expect { helper.protect_marked_words!({ 'input' => masked }, session, {}) }.not_to raise_error
    end

    it 'sends nothing, and changes nothing, when a marked word is in a part that is not masked' do
      allow(helper).to receive(:privacy_pipeline_for).and_return(pipeline)
      [{ 'system' => 'You write for Bob.' },
       { 'instructions' => (['Please ask Bob about this matter and report back to the team'] * 4).join(' ') },
       { 'tools' => [{ 'name' => 'Bob_lookup', 'parameters' => { 'required' => ['Bob'] } }] },
       { 'contents' => [{ 'parts' => [{ 'functionCall' => { 'name' => 'lookup', 'args' => { 'id' => 'Bob', 'role' => 'Bob' } } }] }] },
       { 'input' => [{ 'type' => 'function_call', 'arguments' => JSON.generate('person' => 'Bob') }] }].each do |body|
        before = Marshal.load(Marshal.dump(body))
        expect { helper.protect_marked_words!(body, session, {}) }.to raise_error(Monadic::Utils::Privacy::Outbound::Refused)
        expect(body).to eq(before)
      end
    end

    it 'finds a word written escaped in JSON arguments' do
      quoted = { monadic_state: { privacy: { terms: [{ text: 'A"B', type: 'PERSON' }] } } }
      body = { 'input' => [{ 'type' => 'function_call', 'arguments' => JSON.generate('person' => 'A"B') }] }
      expect { Monadic::Utils::Privacy::Outbound.check_no_marked_words!(quoted, body) }
        .to raise_error(Monadic::Utils::Privacy::Outbound::Refused)
    end

    it 'sends nothing for the chat when the filter is off' do
      allow(helper).to receive(:privacy_pipeline_for).and_return(nil)
      expect { helper.protect_marked_words!({ 'messages' => [] }, session, {}) }
        .to raise_error(Monadic::Utils::Privacy::Outbound::Refused)
    end

    it 'does not take a placeholder or image data for the word itself' do
      words = { monadic_state: { privacy: { terms: [{ text: 'PERSON', type: 'PERSON' }, { text: 'QUJD', type: 'PERSON' }] } } }
      body = { 'messages' => [{ 'role' => 'assistant', 'content' => [
        { 'type' => 'text', 'text' => '<<PERSON_1>>' },
        { 'type' => 'image', 'source' => { 'type' => 'base64', 'data' => 'QUJDQUJD' } },
        { 'type' => 'image_url', 'image_url' => { 'url' => 'data:image/png;base64,QUJDPERSON' } }
      ] }], 'contents' => [{ 'parts' => [{ 'inline_data' => { 'mime_type' => 'image/png', 'data' => 'QUJD' } }] }] }
      expect { Monadic::Utils::Privacy::Outbound.check_no_marked_words!(words, body) }.not_to raise_error
    end

    it 'refuses a helper request whose masking left a marked word' do
      state = { registry: {}, terms: [{ text: 'Bob', type: 'PERSON' }] }
      leaky = double('Pipeline', registry_state: state)
      allow(leaky).to receive(:before_send_to_llm) { |raw| double('Masked', text: raw.text) }
      expect { Monadic::Utils::Privacy::Outbound.mask('Bob', leaky, 'user') }
        .to raise_error(Monadic::Utils::Privacy::Outbound::Refused)
    end
  end

  describe 'speech-to-speech' do
    it 'stays closed in a chat with marked words, the filter on or off' do
      host = Class.new { include WebSocketHelper }.new
      allow(host).to receive(:sts_session_capable?).and_return(true)
      session = real_session(parameters: { 'app_name' => 'ChatOpenAI' },
                             monadic_state: { privacy: { terms: [{ text: 'Bob', type: 'PERSON' }] } })
      expect(host.send(:route_audio_mode, session)).to eq(:privacy_blocked)
    end
  end

  describe 'overlapping marked words' do
    it 'are replaced as one in speech and in a masked file' do
      outbound = Monadic::Utils::Privacy::Outbound
      expect(outbound.replace_union('xABCDEFGHIy', [%w[ABCDEF P], %w[DEFGHI O]])).to eq('xPy')
      pipeline = Monadic::Utils::Privacy::Pipeline.new(
        backend: double('Backend'), config: { enabled: true },
        session: { monadic_state: { privacy: { registry: {}, audit: [], terms: [{ text: 'ABCDEF', type: 'PERSON' }, { text: 'DEFGHI', type: 'ORGANIZATION' }] } } }
      )
      expect(pipeline.sanitize_restored_for_tts('ABCDEFGHI')).not_to include('GHI')
    end
  end

  describe 'a masked file' do
    let(:harness) do
      Class.new do
        include WebSocketHelper
        attr_reader :sent

        def initialize
          @sent = []
        end

        def send_to_client(_connection, payload)
          @sent << payload
        end
      end.new
    end

    it 'holds the marked words nowhere: not in the app state, the Session Context or anything nested' do
      session = {
        messages: [{ 'mid' => 'a', 'role' => 'user', 'text' => 'SecretName', 'app_name' => 'X',
                     'verify' => { 'responses' => [{ 'text' => 'about SecretName' }] } }],
        parameters: { 'app_name' => 'X' },
        monadic_state: { 'app' => { 'entry' => { data: 'SecretName', version: 1, updated_at: 't' } },
                         conversation_context: { 'person' => 'SecretName' }, context_schema: { 'description' => 'SecretName' },
                         privacy: { registry: {}, audit: [], terms: [{ text: 'SecretName', type: 'PERSON' }] } }
      }
      harness.send(:handle_ws_privacy_export, nil, session, { 'encrypt' => false, 'content' => 'masked' })
      written = Base64.strict_decode64(harness.sent.last['content_base64'])
      expect(written).not_to include('SecretName')
      expect(written).to include('<<PERSON_1>>')
    end
  end

  describe 'marks in an imported file, and the number of words' do
    it 'keeps the type a word was marked with last' do
      expect(marks.extract('⟦Acme|person⟧ ⟦Acme|organization⟧').last).to eq([{ text: 'Acme', type: 'ORGANIZATION' }])
    end

    it 'adds no word when they would be too many, and keeps those there' do
      registry = Monadic::Utils::Privacy::Registry.new({})
      registry.add_terms!(Array.new(200) { |i| { text: "w#{i}", type: 'PERSON' } })
      expect { registry.add_terms!([{ text: 'one more', type: 'PERSON' }]) }
        .to raise_error(Monadic::Utils::Privacy::Registry::TooManyTerms)
      expect(registry.terms.size).to eq(200)
    end
  end

  describe 'the helpers that send for the chat' do
    let(:registry) { {} }
    let(:pipeline) do
      reg = registry
      double('Pipeline', registry_state: { registry: reg, terms: [{ text: 'SecretName', type: 'PERSON' }] }).tap do |p|
        allow(p).to receive(:before_send_to_llm) do |raw|
          reg['<<PERSON_1>>'] = 'SecretName' if raw.text.include?('SecretName')
          double('Masked', text: raw.text.gsub('SecretName', '<<PERSON_1>>'))
        end
      end
    end

    def extract(schema)
      session = real_session(parameters: {}, _privacy_pipeline: pipeline,
                             monadic_state: { privacy: { registry: registry, terms: [{ text: 'SecretName', type: 'PERSON' }] } })
      agent = Class.new { include ContextExtractorAgent }.new
      allow(SystemDefaults).to receive(:get_default_model).and_return('test-model')
      allow(agent).to receive(:get_api_key_for_provider).and_return('test-key-not-sent')
      sent = nil
      allow(agent).to receive(:call_provider_api) { |_p, _m, prompt, _k| (sent = prompt) && nil }
      agent.extract_context(session, 'Hi SecretName', 'Hello', 'openai', schema)
      sent
    end

    it 'sends the context extraction with the conversation masked' do
      sent = extract(nil)
      expect(sent).to include('<<PERSON_1>>')
      expect(sent).not_to include('SecretName')
    end

    it 'sends no context extraction when the schema holds a marked word' do
      expect(extract({ 'fields' => [{ 'name' => 'person', 'description' => 'Facts about SecretName' }] })).to be_nil
    end
  end

  describe 'a masked file, again' do
    let(:harness) do
      Class.new do
        include WebSocketHelper
        attr_reader :sent

        def initialize
          @sent = []
        end

        def send_to_client(_connection, payload)
          @sent << payload
        end
      end.new
    end

    def export_with(term, text)
      session = { messages: [{ 'mid' => 'a', 'role' => 'user', 'text' => text, 'app_name' => 'X' }],
                  parameters: { 'app_name' => 'X' },
                  monadic_state: { privacy: { registry: {}, audit: [], terms: [{ text: term, type: 'PERSON' }] } } }
      harness.send(:handle_ws_privacy_export, nil, session, { 'encrypt' => false, 'content' => 'masked' })
      JSON.parse(Base64.strict_decode64(harness.sent.last['content_base64']))
    end

    it 'does not mask inside a placeholder it wrote, and keeps the role' do
      file = export_with('PERSON', 'PERSON here')
      expect(file['messages'].first['text']).to eq('<<PERSON_1>> here')
      file = export_with('user', 'a user here')
      expect(file['messages'].first['role']).to eq('user')
      expect(file['messages'].first['text']).to eq('a <<PERSON_1>> here')
    end

    it 'says its marks were taken out, so its brackets are not read again' do
      file = export_with('Bob', 'Bob wrote ⟦this⟧')
      expect(file['marks_parsed']).to be true
    end
  end

  describe 'data in a request body' do
    let(:session) { { monadic_state: { privacy: { terms: [{ text: 'SecretName', type: 'PERSON' }] } } } }
    let(:outbound) { Monadic::Utils::Privacy::Outbound }

    it 'is passed over only at the places the APIs put images, audio and files' do
      [{ 'system' => 'data: SecretName is the owner' },
       { 'functionCall' => { 'args' => { 'file_data' => 'SecretName' } } },
       { 'functionCall' => { 'args' => { 'inline_data' => { 'data' => 'SecretName' } } } },
       { 'source' => { 'type' => 'base64', 'data' => 'SecretName' } }].each do |body|
        expect { outbound.check_no_marked_words!(session, body) }.to raise_error(outbound::Refused), body.inspect
      end
      [{ 'content' => [{ 'type' => 'image', 'source' => { 'type' => 'base64', 'data' => 'SecretName' } }] },
       { 'content' => [{ 'type' => 'image_url', 'image_url' => { 'url' => 'data:image/png;base64,SecretName' } }] },
       { 'input' => [{ 'type' => 'input_image', 'image_url' => 'data:image/png;base64,SecretName' }] },
       { 'input' => [{ 'type' => 'input_file', 'file_data' => 'SecretName' }] },
       { 'content' => [{ 'type' => 'input_audio', 'input_audio' => { 'data' => 'SecretName' } }] },
       { 'contents' => [{ 'parts' => [{ 'inline_data' => { 'mime_type' => 'image/png', 'data' => 'SecretName' } }] }] }].each do |body|
        expect { outbound.check_no_marked_words!(session, body) }.not_to raise_error, body.inspect
      end
    end
  end

  describe 'tool results of other vendors' do
    let(:helper) { Class.new { include BaseVendorHelper }.new }
    let(:session) { { _privacy_session_enabled: true, monadic_state: { privacy: { registry: {}, audit: [], terms: [{ text: 'Bob', type: 'PERSON' }] } } } }
    let(:pipeline) do
      double('Pipeline').tap do |p|
        allow(p).to receive(:before_send_to_llm) { |raw| double('Masked', text: raw.text.gsub('Bob', '<<PERSON_1>>')) }
      end
    end

    it 'masks Cohere documents (JSON) and texts, keeping the parts and the JSON intact' do
      allow(helper).to receive(:privacy_pipeline_for).and_return(pipeline)
      masked = helper.apply_privacy_to_messages(
        [{ 'role' => 'tool', 'tool_call_id' => 't1', 'content' => [
          { 'type' => 'document', 'document' => { 'id' => 'doc1', 'data' => JSON.generate('result' => 'Bob "the" writer') } },
          { 'type' => 'text', 'text' => 'error about Bob' }
        ] }], session, { privacy: { enabled: true } }
      )
      parts = masked.first['content']
      expect(parts[0]['type']).to eq('document')
      expect(JSON.parse(parts[0]['document']['data'])).to eq('result' => '<<PERSON_1>> "the" writer')
      expect(parts[1]['text']).to eq('error about <<PERSON_1>>')
      expect { helper.protect_marked_words!({ 'messages' => masked }, session, {}) }.not_to raise_error
    end

    it 'masks Gemini function responses' do
      gemini = Class.new do
        include BaseVendorHelper
        include GeminiHelper if defined?(GeminiHelper)
      end.new
      skip 'GeminiHelper is not loaded here' unless gemini.respond_to?(:apply_privacy_to_gemini_contents, true)
      allow(gemini).to receive(:privacy_pipeline_for).and_return(pipeline)
      contents = [{ 'role' => 'user', 'parts' => [{ 'functionResponse' => { 'name' => 'lookup', 'response' => { 'content' => 'Bob wrote' } } }] }]
      masked = gemini.send(:apply_privacy_to_gemini_contents, contents, session, { privacy: { enabled: true } })
      expect(masked[0]['parts'][0]['functionResponse']).to eq('name' => 'lookup', 'response' => { 'content' => '<<PERSON_1>> wrote' })
    end
  end

  describe 'a masked file with JSON in it' do
    let(:harness) do
      Class.new do
        include WebSocketHelper
        attr_reader :sent

        def initialize
          @sent = []
        end

        def send_to_client(_connection, payload)
          @sent << payload
        end
      end.new
    end

    it 'masks a word written escaped in a JSON value, and keeps the JSON valid' do
      word = 'A"B'
      session = { messages: [{ 'mid' => 'a', 'role' => 'user', 'text' => word, 'app_name' => 'X' }],
                  parameters: { 'app_name' => 'X' },
                  monadic_state: { conversation_context: { 'json' => JSON.generate('person' => word) },
                                   privacy: { registry: {}, audit: [], terms: [{ text: word, type: 'PERSON' }] } } }
      harness.send(:handle_ws_privacy_export, nil, session, { 'encrypt' => false, 'content' => 'masked' })
      file = JSON.parse(Base64.strict_decode64(harness.sent.last['content_base64']))
      json_value = file.dig('session_context', 'json') || file.dig('monadic_state', 'conversation_context', 'json')
      expect(JSON.parse(json_value)).to eq('person' => '<<PERSON_1>>')
      expect(JSON.generate(file)).not_to include('A\\"B')
    end
  end

  describe 'attachments and data, again' do
    let(:outbound) { Monadic::Utils::Privacy::Outbound }
    let(:session) { { monadic_state: { privacy: { terms: [{ text: 'SecretName', type: 'PERSON' }] } } } }

    it 'reads a tool argument shaped like an attachment' do
      [{ 'contents' => [{ 'parts' => [{ 'functionCall' => { 'name' => 'lookup', 'args' => { 'type' => 'input_file', 'file_data' => 'SecretName' } } }] }] },
       { 'contents' => [{ 'parts' => [{ 'functionCall' => { 'name' => 'lookup', 'args' => { 'parts' => [{ 'inlineData' => { 'data' => 'SecretName' } }] } } }] }] },
       { 'messages' => [{ 'role' => 'assistant', 'content' => [{ 'type' => 'tool_use', 'input' => { 'type' => 'image', 'source' => { 'type' => 'base64', 'data' => 'SecretName' } } }] }] }].each do |body|
        expect { outbound.check_no_marked_words!(session, body) }.to raise_error(outbound::Refused), body.inspect
      end
    end

    it 'passes over the images Mistral, Cohere and Ollama send' do
      [{ 'messages' => [{ 'role' => 'user', 'content' => [{ 'type' => 'image_url', 'image_url' => 'data:image/png;base64,SecretName' }] }] },
       { 'messages' => [{ 'role' => 'user', 'content' => [{ 'type' => 'image', 'image' => 'data:image/png;base64,SecretName' }] }] },
       { 'messages' => [{ 'role' => 'user', 'content' => 'look', 'images' => ['SecretName'] }] }].each do |body|
        expect { outbound.check_no_marked_words!(session, body) }.not_to raise_error, body.inspect
      end
    end

    it 'reads JSON string values, also inside JSON' do
      word = 'A"B'
      quoted = { monadic_state: { privacy: { terms: [{ text: word, type: 'PERSON' }] } } }
      [{ 'system' => JSON.generate(word) },
       { 'arguments' => JSON.generate('person' => JSON.generate(word)) }].each do |body|
        expect { outbound.check_no_marked_words!(quoted, body) }.to raise_error(outbound::Refused), body.inspect
      end
    end
  end

  describe 'a masked file with JSON string values' do
    let(:harness) do
      Class.new do
        include WebSocketHelper
        attr_reader :sent

        def initialize
          @sent = []
        end

        def send_to_client(_connection, payload)
          @sent << payload
        end
      end.new
    end

    it 'masks them, written as JSON again' do
      word = 'A"B'
      [JSON.generate(word), JSON.generate('person' => JSON.generate(word))].each do |json|
        session = { messages: [{ 'mid' => 'a', 'role' => 'user', 'text' => 'x', 'app_name' => 'X' }],
                    parameters: { 'app_name' => 'X' },
                    monadic_state: { conversation_context: { 'json' => json },
                                     privacy: { registry: {}, audit: [], terms: [{ text: word, type: 'PERSON' }] } } }
        harness.send(:handle_ws_privacy_export, nil, session, { 'encrypt' => false, 'content' => 'masked' })
        file = JSON.parse(Base64.strict_decode64(harness.sent.last['content_base64']))
        value = file.dig('session_context', 'json')
        decoded = JSON.parse(value)
        decoded = JSON.parse(decoded['person']) if decoded.is_a?(Hash)
        expect(decoded).to eq('<<PERSON_1>>')
      end
    end
  end

  describe 'AI User and the helpers that mask text' do
    let(:outbound) { Monadic::Utils::Privacy::Outbound }

    def pipeline_with(word, registry = {})
      double('Pipeline', registry_state: { registry: registry, terms: [{ text: word, type: 'PERSON' }] }).tap do |p|
        allow(p).to receive(:before_send_to_llm) { |raw| double('Masked', text: raw.text.gsub(word, '<<PERSON_1>>')) }
      end
    end

    it 'finds a word written as JSON in what the masking gave back' do
      word = 'A"B'
      expect { outbound.mask(JSON.generate(word), pipeline_with(word), 'user') }.to raise_error(outbound::Refused)
    end

    it 'does not ask AI User when a marked word is in its own instructions' do
      session = real_session(parameters: {}, messages: [{ 'role' => 'user', 'text' => 'Hello' }],
                             _privacy_pipeline: pipeline_with('natural'),
                             monadic_state: { privacy: { registry: {}, terms: [{ text: 'natural', type: 'PERSON' }] } })
      agent = Class.new { include AIUserAgent }.new
      app = double('app')
      allow(app).to receive(:send_query)
      allow(agent).to receive(:find_chat_app_for_provider).and_return(['ChatOpenAI', app])
      allow(agent).to receive(:default_model_for_provider).and_return('test-model')
      result = agent.process_ai_user(session, { 'ai_user_provider' => 'openai' })
      expect(app).not_to have_received(:send_query)
      expect(result['type']).to eq('error')
    end
  end

  # What is added after a helper's check, speech, uploads, titles and
  # Knowledge Base results.
  describe 'the last boundary of each helper' do
    let(:outbound) { Monadic::Utils::Privacy::Outbound }

    def marked(word)
      { _privacy_session_enabled: true, parameters: {}, messages: [{ 'role' => 'user', 'text' => 'Hello' }],
        monadic_state: { privacy: { registry: {}, terms: [{ text: word, type: 'PERSON' }] } } }
    end

    it 'finds a word written escaped in the middle of a text' do
      expect(outbound.holds_word?('note: {"person":"A\\"B"} here', ['A"B'])).to be true
    end

    it 'does not ask AI User when an instruction added for a provider holds a marked word' do
      session = real_session(marked('explanations').merge(_privacy_pipeline: double('Pipeline', registry_state: { registry: {}, terms: [{ text: 'explanations', type: 'PERSON' }] }).tap { |p| allow(p).to receive(:before_send_to_llm) { |raw| double('M', text: raw.text) } }))
      agent = Class.new { include AIUserAgent }.new
      app = double('app')
      allow(app).to receive(:send_query)
      allow(agent).to receive(:find_chat_app_for_provider).and_return(['ChatClaude', app])
      allow(agent).to receive(:default_model_for_provider).and_return('test-model')
      result = agent.process_ai_user(session, { 'ai_user_provider' => 'anthropic' })
      expect(app).not_to have_received(:send_query)
      expect(result['type']).to eq('error')
    end

    it 'checks the context extraction request at its HTTP boundary' do
      agent = Class.new { include ContextExtractorAgent }.new
      Thread.current[:monadic_extraction_session] = marked('JSON only')
      expect(Net::HTTP).not_to receive(:new)
      expect(agent.make_http_request(URI('https://example.invalid/'), { 'messages' => [{ 'content' => 'return JSON only' }] }, {})).to be_nil
    ensure
      Thread.current[:monadic_extraction_session] = nil
    end

    it 'does not speak a marked word, however it is written' do
      host = Class.new { include WebSocketHelper }.new
      errors = []
      allow(host).to receive(:send_error) { |m, *| errors << m }
      session = marked('A"B').merge(_privacy_pipeline: double('Pipeline', sanitize_restored_for_tts: JSON.generate('A"B')))
      allow(Monadic::Utils::Privacy::Outbound).to receive(:pipeline!).and_return(session[:_privacy_pipeline])
      expect(host.send(:privacy_sanitize_tts_text, 'x', session)).to be_nil
      expect(errors.size).to eq(1)
    end

    it 'uploads no file ahead of the request in a chat with marked words' do
      helper = Class.new { include OpenAIHelper }.new if defined?(OpenAIHelper)
      skip 'OpenAIHelper is not loaded here' unless helper
      expect(Monadic::Utils::OpenAIFileInputsCache).not_to receive(:resolve_or_upload)
      img = { 'data' => 'data:application/pdf;base64,QUJD', 'title' => 'SecretName.pdf', 'type' => 'application/pdf' }
      expect(helper.resolve_file_id_for_input(marked('SecretName'), img)).to be_nil
    end

    it 'asks for no title when the request holds a marked word' do
      require_relative '../../../../lib/monadic/library/title_suggester'
      suggester = Monadic::Library::TitleSuggester
      app = double('app')
      allow(app).to receive(:send_query)
      allow(suggester).to receive_messages(derive_provider: 'openai', api_key_present?: true, find_chat_app: ['ChatOpenAI', app])
      allow(SystemDefaults).to receive(:get_default_model).and_return('test-model')
      title = suggester.suggest(messages: [{ 'role' => 'user', 'text' => 'Hello' }], app_name: 'ChatOpenAI',
                                session: marked('concise'))
      expect(app).not_to have_received(:send_query)
      expect(title).to be_nil
    end
  end

  describe 'speech as the TTS service receives it, and the parallel panel' do
    def marked(word)
      { _privacy_session_enabled: true, parameters: {}, messages: [],
        monadic_state: { privacy: { registry: {}, terms: [{ text: word, type: 'PERSON' }] } } }
    end

    it 'does not speak a word that the provider conversion brings back' do
      host = Class.new { include WebSocketHelper }.new
      allow(host).to receive(:send_error)
      session = marked('SecretName').merge(_privacy_pipeline: double('Pipeline', sanitize_restored_for_tts: 'Secret<loud>Name'))
      allow(Monadic::Utils::Privacy::Outbound).to receive(:pipeline!).and_return(session[:_privacy_pipeline])
      allow(host).to receive(:tts_text_as_sent).and_return('SecretName')
      expect(host.send(:privacy_sanitize_tts_text, 'x', session, 'elevenlabs-v3')).to be_nil
    end

    it 'checks each target of the parallel panel in the chat it runs for' do
      require_relative '../../../../lib/monadic/mcp/conduit'
      conduit = Monadic::MCP::Conduit
      skip 'Conduit has no run_in_parallel here' unless conduit.respond_to?(:run_in_parallel, true)
      Thread.current[:rack_session] = marked('SecretName')
      seen = conduit.send(:run_in_parallel, [{ provider: 'openai', model: 'm' }]) { |_t| Thread.current[:rack_session] }
      expect(seen.first).to include(monadic_state: anything)
    ensure
      Thread.current[:rack_session] = nil
    end
  end
end
