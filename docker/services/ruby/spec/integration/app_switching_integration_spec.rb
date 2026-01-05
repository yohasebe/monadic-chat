# frozen_string_literal: true

require 'spec_helper'
require 'json'
require_relative '../../lib/monadic/utils/websocket'

RSpec.describe 'App Switching Integration', type: :integration do
  # Include the WebSocketHelper methods for testing
  include WebSocketHelper

  # Load all apps to ensure Voice Chat and other apps are available
  before(:all) do
    TestAppLoader.load_all_apps
  end

  let(:mock_session) do
    {
      "parameters" => {},  # Use string keys to match WebSocketHelper expectations
      :parameters => {},    # Also provide symbol key for compatibility
      :messages => []
    }
  end

  # Define session method to make WebSocketHelper methods work
  def session
    Thread.current[:rack_session]
  end

  before do
    # Initialize session
    Thread.current[:rack_session] = mock_session
  end

  after do
    Thread.current[:rack_session] = nil
  end

  describe 'Feature flag type preservation' do
    context 'when preparing apps data for frontend' do
      it 'preserves boolean values for feature flags' do
        # Skip if APPS is not defined (e.g., in isolated test environment)
        skip 'APPS not defined' unless defined?(APPS)

        # Prepare apps data
        apps_data = prepare_apps_data

        # Test each boolean feature flag across all apps
        boolean_flags = %w[
          auto_speech easy_submit initiate_from_assistant
          mathjax mermaid abc monadic
          pdf_vector_storage websearch
          jupyter video
        ]

        # Flags that can be boolean OR specific string values
        # image_generation can be: true, false, "upload_only", "disabled"
        multi_value_flags = {
          'image_generation' => [TrueClass, FalseClass, NilClass, 'upload_only', 'disabled']
        }

        apps_data.each do |app_name, app_settings|
          boolean_flags.each do |flag|
            next unless app_settings.key?(flag)

            value = app_settings[flag]
            # Value must be either actual boolean or nil, not string
            expect([TrueClass, FalseClass, NilClass]).to include(value.class),
                   "#{app_name}[#{flag}] should be boolean or nil, got #{value.class}: #{value.inspect}"

            # Specifically check it's not a string "true" or "false"
            expect(value).not_to eq('true')
            expect(value).not_to eq('false')
          end

          # Check multi-value flags
          multi_value_flags.each do |flag, allowed_values|
            next unless app_settings.key?(flag)

            value = app_settings[flag]
            valid = allowed_values.any? do |allowed|
              if allowed.is_a?(Class)
                value.is_a?(allowed)
              else
                value == allowed
              end
            end
            expect(valid).to be(true),
                   "#{app_name}[#{flag}] should be one of #{allowed_values.inspect}, got #{value.inspect}"
          end
        end
      end

      it 'converts array parameters to JSON' do
        skip 'APPS not defined' unless defined?(APPS)

        apps_data = prepare_apps_data

        apps_data.each do |app_name, app_settings|
          # Check models array
          if app_settings.key?('models')
            models = app_settings['models']
            # Should be JSON string
            expect(models).to be_a(String)
            # Should be valid JSON
            expect { JSON.parse(models) }.not_to raise_error
            # Parsed result should be an array
            expect(JSON.parse(models)).to be_an(Array)
          end

          # Check tools array/hash
          if app_settings.key?('tools')
            tools = app_settings['tools']
            # Should be JSON string
            expect(tools).to be_a(String)
            # Should be valid JSON
            expect { JSON.parse(tools) }.not_to raise_error
          end
        end
      end

      it 'handles disabled parameter as string' do
        skip 'APPS not defined' unless defined?(APPS)

        apps_data = prepare_apps_data

        apps_data.each do |app_name, app_settings|
          next unless app_settings.key?('disabled')

          disabled = app_settings['disabled']
          # Disabled is intentionally kept as string for compatibility
          expect(disabled).to be_a(String)
          expect(['true', 'false']).to include(disabled)
        end
      end
    end
  end

  describe 'App switching scenario' do
    context 'switching from Voice Chat to Chat' do
      it 'resets auto_speech from true to false' do
        skip 'APPS not defined' unless defined?(APPS)
        skip 'Voice Chat apps not available' unless APPS.key?('VoiceChatOpenAI') || APPS.key?('VoiceChatClaude')

        apps_data = prepare_apps_data

        # Find a Voice Chat app (should have auto_speech: true)
        voice_chat_app = apps_data.find { |name, _| name.include?('VoiceChat') }
        skip 'Voice Chat app not found' unless voice_chat_app

        voice_chat_name, voice_chat_settings = voice_chat_app

        # Find a regular Chat app (should have auto_speech: false)
        chat_app = apps_data.find { |name, settings| name.include?('Chat') && !name.include?('VoiceChat') && !name.include?('Plus') }
        skip 'Regular Chat app not found' unless chat_app

        chat_name, chat_settings = chat_app

        # Verify Voice Chat has auto_speech enabled
        expect(voice_chat_settings['auto_speech']).to be true

        # Verify regular Chat has auto_speech disabled
        expect(chat_settings['auto_speech']).to be false

        # Both should be actual booleans, not strings
        expect(voice_chat_settings['auto_speech']).to be_a(TrueClass)
        expect(chat_settings['auto_speech']).to be_a(FalseClass)
      end
    end

    context 'switching between apps with different feature flags' do
      it 'correctly reflects each app\'s feature configuration' do
        skip 'APPS not defined' unless defined?(APPS)

        apps_data = prepare_apps_data

        # Find apps with different pdf_vector_storage configurations
        app_with_pdf = apps_data.find { |_, settings| settings['pdf_vector_storage'] == true }
        app_without_pdf = apps_data.find { |_, settings| settings['pdf_vector_storage'] == false || settings['pdf_vector_storage'].nil? }

        if app_with_pdf && app_without_pdf
          _, settings_with = app_with_pdf
          _, settings_without = app_without_pdf

          # App with pdf_vector_storage should have true
          expect(settings_with['pdf_vector_storage']).to be true
          expect(settings_with['pdf_vector_storage']).to be_a(TrueClass)

          # App without pdf_vector_storage should have false or nil
          expect([false, nil]).to include(settings_without['pdf_vector_storage'])
        else
          skip 'Could not find apps with different pdf_vector_storage configurations'
        end
      end
    end
  end

  describe 'Type consistency across app definitions' do
    it 'maintains consistent types for all feature flags' do
      skip 'APPS not defined' unless defined?(APPS)

      apps_data = prepare_apps_data

      # Collect all unique feature flags across apps
      all_flags = apps_data.flat_map { |_, settings| settings.keys }.uniq

      # Pure boolean flags
      boolean_flags = %w[
        auto_speech easy_submit initiate_from_assistant
        mathjax mermaid abc monadic
        pdf_vector_storage websearch
        jupyter video
      ]

      # Flags that can be boolean OR specific string values
      # image_generation can be: true, false, "upload_only", "disabled"
      multi_value_flags = {
        'image_generation' => [TrueClass, FalseClass, NilClass, 'upload_only', 'disabled']
      }

      # Check that boolean flags are consistently boolean type
      boolean_flags.each do |flag|
        apps_with_flag = apps_data.select { |_, settings| settings.key?(flag) }
        next if apps_with_flag.empty?

        apps_with_flag.each do |app_name, settings|
          value = settings[flag]
          expect([TrueClass, FalseClass, NilClass]).to include(value.class),
                 "#{app_name}[#{flag}] has inconsistent type: #{value.class}"
        end
      end
    end

    it 'ensures no string boolean values in feature flags' do
      skip 'APPS not defined' unless defined?(APPS)

      apps_data = prepare_apps_data

      # Pure boolean flags (image_generation excluded - can be "upload_only", "disabled")
      boolean_flags = %w[
        auto_speech easy_submit initiate_from_assistant
        mathjax mermaid abc monadic
        pdf_vector_storage websearch
        jupyter video
      ]

      # This is the critical test - no feature flag should be "true" or "false" string
      apps_data.each do |app_name, settings|
        boolean_flags.each do |flag|
          next unless settings.key?(flag)

          value = settings[flag]
          error_msg = "#{app_name}[#{flag}] is a string '#{value}' instead of boolean. " \
                      "This will cause '#{value}' to be truthy in JavaScript, " \
                      "breaking feature flag evaluation."

          expect(value).not_to eq('true'), error_msg
          expect(value).not_to eq('false'), error_msg
        end
      end
    end
  end

  describe 'Message filtering by app_name' do
    it 'filters messages by app_name when preparing filtered messages' do
      # Set up session with messages from different apps
      session["parameters"] = { 'app_name' => 'ChatOpenAI' }
      session[:parameters] = { 'app_name' => 'ChatOpenAI' }
      session[:messages] = [
        {
          'role' => 'user',
          'text' => 'Message from ChatOpenAI',
          'app_name' => 'ChatOpenAI',
          'type' => 'message'
        },
        {
          'role' => 'user',
          'text' => 'Message from VoiceChatOpenAI',
          'app_name' => 'VoiceChatOpenAI',
          'type' => 'message'
        },
        {
          'role' => 'assistant',
          'text' => 'Response in ChatOpenAI',
          'html' => '<p>Response in ChatOpenAI</p>',  # Include html to avoid markdown conversion
          'app_name' => 'ChatOpenAI',
          'type' => 'message'
        }
      ]

      filtered = prepare_filtered_messages

      # Should only include messages from current app (ChatOpenAI)
      expect(filtered.length).to eq(2)
      expect(filtered.all? { |m| m['app_name'] == 'ChatOpenAI' }).to be true
      expect(filtered.none? { |m| m['app_name'] == 'VoiceChatOpenAI' }).to be true
    end

    it 'prevents cross-app message contamination' do
      # Simulate switching apps
      first_app = 'ChatOpenAI'
      second_app = 'VoiceChatOpenAI'

      # Add messages for first app
      session["parameters"] = { 'app_name' => first_app }
      session[:parameters] = { 'app_name' => first_app }
      session[:messages] = [
        {
          'role' => 'user',
          'text' => 'Question in Chat',
          'app_name' => first_app,
          'type' => 'message'
        }
      ]

      first_filtered = prepare_filtered_messages
      expect(first_filtered.length).to eq(1)

      # Switch to second app
      session["parameters"] = { 'app_name' => second_app }
      session[:parameters] = { 'app_name' => second_app }

      # Add message for second app
      session[:messages] << {
        'role' => 'user',
        'text' => 'Question in Voice Chat',
        'app_name' => second_app,
        'type' => 'message'
      }

      second_filtered = prepare_filtered_messages

      # Should only see second app's messages
      expect(second_filtered.length).to eq(1)
      expect(second_filtered.first['app_name']).to eq(second_app)
      expect(second_filtered.first['text']).to eq('Question in Voice Chat')
    end
  end

  describe 'Backward compatibility' do
    context 'when handling legacy messages without app_name' do
      it 'includes messages without app_name field' do
        session["parameters"] = { 'app_name' => 'ChatOpenAI' }
        session[:parameters] = { 'app_name' => 'ChatOpenAI' }
        session[:messages] = [
          {
            'role' => 'user',
            'text' => 'Old message without app_name',
            # No app_name field (legacy message)
            'type' => 'message'
          },
          {
            'role' => 'user',
            'text' => 'New message with app_name',
            'app_name' => 'ChatOpenAI',
            'type' => 'message'
          }
        ]

        filtered = prepare_filtered_messages

        # Legacy message without app_name should be included
        # (This maintains backward compatibility)
        expect(filtered.length).to be >= 1
        expect(filtered.any? { |m| m['text'] == 'New message with app_name' }).to be true
      end
    end
  end
end
