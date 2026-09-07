# frozen_string_literal: true

require_relative '../../../spec_helper'

# The masked export exists so a conversation can be handed to someone else
# without the values the privacy filter detected. Masking the message body is
# not enough on its own: a message also carries the placeholder-to-original
# table the frontend uses to highlight restorations, a vocabulary map holding
# paths on the exporting machine, the model's reasoning (which quotes the
# conversation), and the rendered HTML (built from the restored body).
# Parameters carry prose too — the initial prompt the user wrote, and text the
# run produced.
#
# These examples pin the two rules that keep those out: an allow list decides
# what may be carried at all, and every free-text field it does carry is
# remasked, not just `text`.
RSpec.describe 'Privacy export share boundary' do
  # Load the four methods under test without the surrounding WebSocket module,
  # which pulls in the whole handler stack.
  let(:exporter) do
    src = File.read(
      File.expand_path('../../../../lib/monadic/utils/websocket/privacy_handler.rb', __dir__)
    )
    constants = src.scan(
      /^  PRIVACY_(?:EXPORT_MESSAGE_KEYS|REMASK_MESSAGE_FIELDS|EXPORT_PARAMETER_KEYS|REMASK_PARAMETER_KEYS) = %w\[.*?\]\.freeze/m
    ).join("\n")
    methods = %w[
      privacy_clean_messages privacy_remask_messages
      privacy_export_parameters privacy_remask_parameters
    ].map { |name| src[/private def #{name}.*?^  end/m] }

    expect(constants.scan('PRIVACY_').size).to eq(4),
      'expected four allow/remask constants; the source has been reorganized'
    expect(methods).to all(be_a(String))

    Module.new.tap do |m|
      m.module_eval("#{constants}\n#{methods.join("\n").gsub('private def', 'def self.')}")
    end
  end

  # One synthetic value, planted in every place a message or parameter can
  # carry prose. Using the same string throughout means a single search over
  # the payload answers "did anything leak".
  let(:pii) { 'Example Person' }
  let(:local_path) { '/Users/someone/private/notes.md' }
  let(:registry) { { '<<PERSON_1>>' => pii } }

  let(:session) do
    {
      messages: [{
        'role' => 'assistant',
        'mid' => 'abc',
        'text' => "Hello #{pii}",
        'thinking' => "reasoning about #{pii}",
        'html' => "<p>Hello #{pii}</p>",
        'tokens' => 12,
        'active' => true,
        'privacy_known_entities' => [
          { 'placeholder' => '<<PERSON_1>>', 'entity_type' => 'PERSON', 'original' => pii }
        ],
        'vocabulary_map' => { 'TOKEN' => local_path },
        '_privacy_internal' => { 'secret' => pii }
      }],
      parameters: {
        'app_name' => 'Chat',
        'model' => 'gpt-5.6-terra',
        'initial_prompt' => "You are helping #{pii} with grammar.",
        'tool_results' => "#{pii} lives at 1-2-3",
        'help_topics_prev_queries' => [pii],
        'initiate_from_assistant' => true
      }
    }
  end

  let(:payload) do
    messages = exporter.privacy_remask_messages(
      exporter.privacy_clean_messages(session[:messages]), registry
    )
    parameters = exporter.privacy_remask_parameters(
      exporter.privacy_export_parameters(session), registry
    )
    { 'messages' => messages, 'parameters' => parameters }
  end

  describe 'a masked export' do
    it 'masks the message body' do
      # Positive control: without this the leak checks below would pass on a
      # payload where nothing was masked at all.
      expect(payload['messages'].first['text']).to eq('Hello <<PERSON_1>>')
    end

    it 'carries the detected value nowhere' do
      expect(JSON.generate(payload)).not_to include(pii)
    end

    it 'carries no path from the exporting machine' do
      expect(JSON.generate(payload)).not_to include('/Users/')
    end

    it 'drops the placeholder-to-original table' do
      expect(payload['messages'].first).not_to have_key('privacy_known_entities')
    end

    it 'masks every free-text field, not only the body' do
      message = payload['messages'].first

      expect(message['thinking']).to eq('reasoning about <<PERSON_1>>')
      expect(message['html']).to eq('<p>Hello <<PERSON_1>></p>')
      expect(payload['parameters']['initial_prompt'])
        .to eq('You are helping <<PERSON_1>> with grammar.')
    end
  end

  describe 'the allow lists' do
    it 'keeps what the import route reads back' do
      # Dropping one of these would break the round trip rather than leak.
      message = payload['messages'].first

      %w[mid role text thinking tokens active].each do |key|
        expect(message).to have_key(key), "#{key} is needed to restore the conversation"
      end
      expect(payload['parameters']).to include('app_name', 'model', 'initial_prompt')
    end

    it 'drops a key nobody vetted for sharing' do
      # The failure this replaces: the old deny list named `_privacy*` only, so
      # vocabulary_map shipped once it was added.
      expect(payload['messages'].first).not_to have_key('vocabulary_map')
      expect(payload['parameters']).not_to have_key('tool_results')
    end

    it 'still withholds initiate_from_assistant' do
      # Importing it would start an assistant turn by itself.
      expect(payload['parameters']).not_to have_key('initiate_from_assistant')
    end
  end

  describe 'the export path wires both steps in' do
    # The examples above call the four methods directly, so they keep passing
    # if handle_ws_privacy_export stops calling one of them — the "mechanism
    # exists but is not wired" failure this whole change is about. Read the
    # assembly instead and check both remaskings happen under the masked
    # branch.
    let(:source) do
      File.read(
        File.expand_path('../../../../lib/monadic/utils/websocket/privacy_handler.rb', __dir__)
      )
    end

    let(:masked_branch) do
      branch = source[/if content_kind == "masked" && !registry\.empty\?.*?^    end/m]
      expect(branch).to be_a(String), 'the masked-export branch has moved or been renamed'
      branch
    end

    it 'remasks the messages' do
      expect(masked_branch).to include('privacy_remask_messages(messages, registry)')
    end

    it 'remasks the parameters' do
      expect(masked_branch).to include('privacy_remask_parameters(parameters, registry)')
    end

    it 'builds parameters through the allow list' do
      expect(source).to include('parameters = privacy_export_parameters(session)')
    end
  end

  describe 'an unmasked export' do
    it 'still applies the allow list' do
      # "restored" content skips remasking, but the table and the local paths
      # are not the user's conversation and stay out either way.
      cleaned = exporter.privacy_clean_messages(session[:messages]).first

      expect(cleaned).not_to have_key('privacy_known_entities')
      expect(cleaned).not_to have_key('vocabulary_map')
      expect(cleaned['text']).to include(pii), 'restored content keeps the body as-is'
    end
  end
end
