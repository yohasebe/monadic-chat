# frozen_string_literal: true

require 'spec_helper'
require 'json'
require_relative '../../lib/monadic/utils/websocket'

RSpec.describe 'WebSocket Tab Isolation', type: :integration do
  # Test session state management at the module level
  # This tests the core isolation mechanism without requiring full WebSocket server

  let(:tab_id_1) { 'test-tab-id-1' }
  let(:tab_id_2) { 'test-tab-id-2' }
  let(:tab_id_3) { 'test-tab-id-3' }

  before(:each) do
    # Clean up session state before each test
    WebSocketHelper.instance_variable_set(:@session_state, {})
    WebSocketHelper.class_variable_set(:@@session_state, {})
  end

  after(:each) do
    # Clean up after each test
    WebSocketHelper.instance_variable_set(:@session_state, {})
    WebSocketHelper.class_variable_set(:@@session_state, {})
  end

  describe 'Session state isolation' do
    context 'when multiple tabs have different session data' do
      it 'maintains separate sessions for different tab_ids' do
        # Tab 1: Create session with messages
        messages_tab1 = [
          { 'role' => 'user', 'text' => 'Hello from tab 1', 'app_name' => 'ChatOpenAI' },
          { 'role' => 'assistant', 'text' => 'Response for tab 1', 'app_name' => 'ChatOpenAI' }
        ]
        parameters_tab1 = { 'app_name' => 'ChatOpenAI', 'temperature' => 0.7 }

        WebSocketHelper.update_session_state(
          tab_id_1,
          messages: messages_tab1,
          parameters: parameters_tab1
        )

        # Tab 2: Create session with different messages
        messages_tab2 = [
          { 'role' => 'user', 'text' => 'Hello from tab 2', 'app_name' => 'VoiceChatOpenAI' }
        ]
        parameters_tab2 = { 'app_name' => 'VoiceChatOpenAI', 'temperature' => 0.9 }

        WebSocketHelper.update_session_state(
          tab_id_2,
          messages: messages_tab2,
          parameters: parameters_tab2
        )

        # Verify tab 1 state is preserved
        state1 = WebSocketHelper.fetch_session_state(tab_id_1)
        expect(state1).not_to be_nil
        expect(state1[:messages].length).to eq(2)
        expect(state1[:messages][0]['text']).to eq('Hello from tab 1')
        expect(state1[:parameters]['app_name']).to eq('ChatOpenAI')
        expect(state1[:parameters]['temperature']).to eq(0.7)

        # Verify tab 2 state is preserved and independent
        state2 = WebSocketHelper.fetch_session_state(tab_id_2)
        expect(state2).not_to be_nil
        expect(state2[:messages].length).to eq(1)
        expect(state2[:messages][0]['text']).to eq('Hello from tab 2')
        expect(state2[:parameters]['app_name']).to eq('VoiceChatOpenAI')
        expect(state2[:parameters]['temperature']).to eq(0.9)

        # Verify states are truly independent (modifying one doesn't affect the other)
        state1[:messages] << { 'role' => 'user', 'text' => 'Modified in test' }
        state2_check = WebSocketHelper.fetch_session_state(tab_id_2)
        expect(state2_check[:messages].length).to eq(1)  # Should still be 1
      end

      it 'handles empty sessions correctly' do
        # Create empty session
        WebSocketHelper.update_session_state(
          tab_id_1,
          messages: [],
          parameters: {}
        )

        state = WebSocketHelper.fetch_session_state(tab_id_1)
        expect(state).not_to be_nil
        expect(state[:messages]).to eq([])
        expect(state[:parameters]).to eq({})
      end

      it 'returns nil for non-existent tab_id' do
        state = WebSocketHelper.fetch_session_state('non-existent-tab-id')
        expect(state).to be_nil
      end
    end
  end

  describe 'Session restoration after reconnection' do
    context 'when same tab_id reconnects' do
      it 'restores previous session data' do
        # Initial connection: Create session
        original_messages = [
          { 'role' => 'user', 'text' => 'Message 1', 'app_name' => 'ChatOpenAI' },
          { 'role' => 'assistant', 'text' => 'Response 1', 'app_name' => 'ChatOpenAI' }
        ]
        original_parameters = { 'app_name' => 'ChatOpenAI', 'model' => 'gpt-4' }

        WebSocketHelper.update_session_state(
          tab_id_1,
          messages: original_messages,
          parameters: original_parameters
        )

        # Simulate reconnection: Fetch saved state
        restored_state = WebSocketHelper.fetch_session_state(tab_id_1)

        # Verify restored state matches original
        expect(restored_state).not_to be_nil
        expect(restored_state[:messages].length).to eq(2)
        expect(restored_state[:messages][0]['text']).to eq('Message 1')
        expect(restored_state[:messages][1]['text']).to eq('Response 1')
        expect(restored_state[:parameters]['app_name']).to eq('ChatOpenAI')
        expect(restored_state[:parameters]['model']).to eq('gpt-4')
      end

      it 'allows adding new messages after restoration' do
        # Initial session
        initial_messages = [
          { 'role' => 'user', 'text' => 'Initial message', 'app_name' => 'ChatOpenAI' }
        ]

        WebSocketHelper.update_session_state(
          tab_id_1,
          messages: initial_messages,
          parameters: { 'app_name' => 'ChatOpenAI' }
        )

        # Restore and add new message
        restored_state = WebSocketHelper.fetch_session_state(tab_id_1)
        restored_messages = restored_state[:messages]
        restored_messages << { 'role' => 'assistant', 'text' => 'New response', 'app_name' => 'ChatOpenAI' }

        # Update session with new messages
        WebSocketHelper.update_session_state(
          tab_id_1,
          messages: restored_messages,
          parameters: restored_state[:parameters]
        )

        # Verify updated session
        final_state = WebSocketHelper.fetch_session_state(tab_id_1)
        expect(final_state[:messages].length).to eq(2)
        expect(final_state[:messages][1]['text']).to eq('New response')
      end
    end
  end

  describe 'Session isolation with tab_id changes' do
    context 'when tab_id changes' do
      it 'creates a new independent session' do
        # Original tab session
        original_messages = [
          { 'role' => 'user', 'text' => 'Original tab message', 'app_name' => 'ChatOpenAI' }
        ]
        original_parameters = { 'app_name' => 'ChatOpenAI', 'temperature' => 0.5 }

        WebSocketHelper.update_session_state(
          tab_id_1,
          messages: original_messages,
          parameters: original_parameters
        )

        # New tab with different ID
        new_messages = [
          { 'role' => 'user', 'text' => 'New tab message', 'app_name' => 'VoiceChatOpenAI' }
        ]
        new_parameters = { 'app_name' => 'VoiceChatOpenAI', 'temperature' => 0.9 }

        WebSocketHelper.update_session_state(
          tab_id_2,
          messages: new_messages,
          parameters: new_parameters
        )

        # Verify original session unchanged
        original_state = WebSocketHelper.fetch_session_state(tab_id_1)
        expect(original_state[:messages][0]['text']).to eq('Original tab message')
        expect(original_state[:parameters]['app_name']).to eq('ChatOpenAI')
        expect(original_state[:parameters]['temperature']).to eq(0.5)

        # Verify new session is independent
        new_state = WebSocketHelper.fetch_session_state(tab_id_2)
        expect(new_state[:messages][0]['text']).to eq('New tab message')
        expect(new_state[:parameters]['app_name']).to eq('VoiceChatOpenAI')
        expect(new_state[:parameters]['temperature']).to eq(0.9)
      end

      it 'does not restore session when tab_id is different' do
        # Create session with tab_id_1
        WebSocketHelper.update_session_state(
          tab_id_1,
          messages: [{ 'role' => 'user', 'text' => 'Tab 1 message' }],
          parameters: { 'app_name' => 'ChatOpenAI' }
        )

        # Try to fetch with different tab_id
        state = WebSocketHelper.fetch_session_state(tab_id_3)
        expect(state).to be_nil
      end
    end
  end

  describe 'Deep cloning of session data' do
    context 'when session state is fetched' do
      it 'returns deep cloned data to prevent unintended mutations' do
        original_messages = [
          { 'role' => 'user', 'text' => 'Original text', 'metadata' => { 'timestamp' => '2025-01-09' } }
        ]
        original_parameters = { 'app_name' => 'ChatOpenAI', 'options' => { 'stream' => true } }

        WebSocketHelper.update_session_state(
          tab_id_1,
          messages: original_messages,
          parameters: original_parameters
        )

        # Fetch state and modify it
        fetched_state1 = WebSocketHelper.fetch_session_state(tab_id_1)
        fetched_state1[:messages][0]['text'] = 'Modified text'
        fetched_state1[:parameters]['app_name'] = 'ModifiedApp'

        # Fetch again and verify original data is unchanged
        fetched_state2 = WebSocketHelper.fetch_session_state(tab_id_1)
        expect(fetched_state2[:messages][0]['text']).to eq('Original text')
        expect(fetched_state2[:parameters]['app_name']).to eq('ChatOpenAI')
      end
    end
  end

  describe 'Concurrent access to session state' do
    context 'when multiple threads access session state simultaneously' do
      it 'maintains thread safety' do
        threads = []
        errors = []

        # Create multiple threads that update different sessions
        10.times do |i|
          threads << Thread.new do
            begin
              tab_id = "thread-tab-#{i}"
              messages = [{ 'role' => 'user', 'text' => "Message from thread #{i}" }]
              parameters = { 'app_name' => 'ChatOpenAI', 'thread_id' => i }

              WebSocketHelper.update_session_state(
                tab_id,
                messages: messages,
                parameters: parameters
              )

              # Verify immediately
              state = WebSocketHelper.fetch_session_state(tab_id)
              raise "State mismatch for thread #{i}" unless state[:parameters]['thread_id'] == i
            rescue StandardError => e
              errors << e
            end
          end
        end

        threads.each(&:join)

        expect(errors).to be_empty

        # Verify all sessions were created correctly
        10.times do |i|
          state = WebSocketHelper.fetch_session_state("thread-tab-#{i}")
          expect(state).not_to be_nil
          expect(state[:parameters]['thread_id']).to eq(i)
        end
      end
    end
  end

  describe 'Session state with different app configurations' do
    context 'when switching between apps in same tab' do
      it 'preserves all messages but updates parameters' do
        # Start with ChatOpenAI
        initial_messages = [
          { 'role' => 'user', 'text' => 'Question in Chat', 'app_name' => 'ChatOpenAI' }
        ]
        initial_parameters = { 'app_name' => 'ChatOpenAI', 'temperature' => 0.7 }

        WebSocketHelper.update_session_state(
          tab_id_1,
          messages: initial_messages,
          parameters: initial_parameters
        )

        # Switch to VoiceChatOpenAI (add new message)
        state = WebSocketHelper.fetch_session_state(tab_id_1)
        updated_messages = state[:messages] + [
          { 'role' => 'user', 'text' => 'Question in Voice Chat', 'app_name' => 'VoiceChatOpenAI' }
        ]
        updated_parameters = { 'app_name' => 'VoiceChatOpenAI', 'auto_speech' => true }

        WebSocketHelper.update_session_state(
          tab_id_1,
          messages: updated_messages,
          parameters: updated_parameters
        )

        # Verify both messages exist
        final_state = WebSocketHelper.fetch_session_state(tab_id_1)
        expect(final_state[:messages].length).to eq(2)
        expect(final_state[:messages][0]['app_name']).to eq('ChatOpenAI')
        expect(final_state[:messages][1]['app_name']).to eq('VoiceChatOpenAI')
        expect(final_state[:parameters]['app_name']).to eq('VoiceChatOpenAI')
        expect(final_state[:parameters]['auto_speech']).to eq(true)
      end
    end
  end

  describe 'Nil and edge case handling' do
    context 'when session_id is nil' do
      it 'handles nil session_id gracefully in update' do
        expect {
          WebSocketHelper.update_session_state(
            nil,
            messages: [{ 'role' => 'user', 'text' => 'Test' }],
            parameters: {}
          )
        }.not_to raise_error
      end

      it 'returns nil when fetching with nil session_id' do
        state = WebSocketHelper.fetch_session_state(nil)
        expect(state).to be_nil
      end
    end

    context 'when messages or parameters are nil' do
      it 'stores empty arrays/hashes instead of nil' do
        WebSocketHelper.update_session_state(
          tab_id_1,
          messages: nil,
          parameters: nil
        )

        state = WebSocketHelper.fetch_session_state(tab_id_1)
        expect(state).not_to be_nil
        expect(state[:messages]).to eq([])
        expect(state[:parameters]).to eq({})
      end
    end
  end
end
