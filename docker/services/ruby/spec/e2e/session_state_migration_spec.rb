require_relative '../spec_helper'
require_relative '../support/e2e_helper'

RSpec.describe "Session State Migration", type: :e2e do
  include E2EHelper

  before(:each) do
    setup_e2e_test
  end

  after(:each) do
    cleanup_e2e_test
  end

  describe "State Management Functionality" do
    context "with backward compatibility" do
      it "maintains Voice Chat reset functionality" do
        # Start Voice Chat app
        visit_app("VoiceChatOpenAI")
        wait_for_app_load
        
        # Click reset button
        find_element(:id, "reset").click
        
        # Check that flags are set correctly
        flags_correct = execute_script(<<-JS)
          return window.SessionState.forceNewSession === true &&
                 window.SessionState.justReset === true &&
                 window.forceNewSession === true &&
                 window.justReset === true;
        JS
        
        expect(flags_correct).to be true
      end
      
      it "preserves message history through state changes" do
        # Start Chat app
        visit_app("ChatOpenAI")
        wait_for_app_load
        
        # Send a message
        send_user_message("Hello, testing state management")
        wait_for_assistant_response
        
        # Check message count
        message_count = execute_script("return window.SessionState.conversation.messages.length;")
        expect(message_count).to be >= 2 # At least user and assistant messages
        
        # Verify messages are accessible through both APIs
        legacy_messages = execute_script("return window.messages ? window.messages.length : 0;")
        new_api_messages = execute_script("return window.SessionState.getMessages().length;")
        
        expect(legacy_messages).to eq(new_api_messages) if legacy_messages > 0
      end
    end
    
    context "with new state management features" do
      it "handles event listeners correctly" do
        visit_app("ChatOpenAI")
        wait_for_app_load
        
        # Set up event listener and trigger event
        event_fired = execute_script(<<-JS)
          let eventFired = false;
          window.SessionState.on('test:event', function(data) {
            eventFired = data === 'test-data';
          });
          window.SessionState.notifyListeners('test:event', 'test-data');
          return eventFired;
        JS
        
        expect(event_fired).to be true
      end
      
      it "saves and restores state from localStorage" do
        visit_app("ChatOpenAI")
        wait_for_app_load
        
        # Set some state
        execute_script(<<-JS)
          window.SessionState.app.current = 'TestApp';
          window.SessionState.session.id = 'test-session-123';
          window.SessionState.conversation.messages = [
            { role: 'user', content: 'test message' }
          ];
          window.SessionState.save();
        JS
        
        # Simulate page refresh by clearing and restoring
        execute_script(<<-JS)
          window.SessionState.app.current = null;
          window.SessionState.session.id = null;
          window.SessionState.conversation.messages = [];
          window.SessionState.restore();
        JS
        
        # Verify restoration
        restored_state = execute_script(<<-JS)
          return {
            app: window.SessionState.app.current,
            sessionId: window.SessionState.session.id,
            messageCount: window.SessionState.conversation.messages.length
          };
        JS
        
        expect(restored_state["app"]).to eq("TestApp")
        expect(restored_state["sessionId"]).to eq("test-session-123")
        expect(restored_state["messageCount"]).to eq(1)
      end
      
      it "validates state integrity" do
        visit_app("ChatOpenAI")
        wait_for_app_load
        
        # Check state validity
        is_valid = execute_script("return window.SessionState.validateState();")
        expect(is_valid).to be true
        
        # Get state snapshot
        snapshot = execute_script("return window.SessionState.getStateSnapshot();")
        
        expect(snapshot).to have_key("session")
        expect(snapshot).to have_key("conversation")
        expect(snapshot).to have_key("app")
        expect(snapshot).to have_key("ui")
        expect(snapshot).to have_key("connection")
        expect(snapshot).to have_key("audio")
      end
    end
    
    context "with concurrent modifications" do
      it "handles rapid state changes safely" do
        visit_app("ChatOpenAI")
        wait_for_app_load
        
        # Perform rapid state changes
        no_errors = execute_script(<<-JS)
          try {
            for (let i = 0; i < 20; i++) {
              window.SessionState.forceNewSession = i % 2 === 0;
              window.SessionState.session.started = i % 3 === 0;
              window.SessionState.addMessage({ role: 'test', content: 'message ' + i });
            }
            return true;
          } catch (error) {
            console.error('State modification error:', error);
            return false;
          }
        JS
        
        expect(no_errors).to be true
        
        # Verify state is still valid
        is_valid = execute_script("return window.SessionState.validateState();")
        expect(is_valid).to be true
      end
      
      it "maintains consistency between old and new APIs" do
        visit_app("ChatOpenAI")
        wait_for_app_load
        
        # Test flag synchronization
        execute_script("window.forceNewSession = true;")
        new_api_value = execute_script("return window.SessionState.session.forceNew;")
        expect(new_api_value).to be true
        
        # Test reverse synchronization
        execute_script("window.SessionState.setResetFlags();")
        legacy_value = execute_script("return window.forceNewSession;")
        expect(legacy_value).to be true
      end
    end
    
    context "error recovery" do
      it "handles localStorage errors gracefully" do
        visit_app("ChatOpenAI")
        wait_for_app_load
        
        # Simulate localStorage being full or unavailable
        save_succeeded = execute_script(<<-JS)
          // Temporarily break localStorage
          const originalSetItem = localStorage.setItem;
          localStorage.setItem = function() { throw new Error('Storage full'); };
          
          try {
            window.SessionState.save();
            // Restore localStorage
            localStorage.setItem = originalSetItem;
            return false; // Should have caught error
          } catch (error) {
            // Restore localStorage
            localStorage.setItem = originalSetItem;
            return true; // Error was not propagated
          }
        JS
        
        # Should handle error gracefully without throwing
        expect(save_succeeded).to be false
        
        # State should still be valid
        is_valid = execute_script("return window.SessionState.validateState();")
        expect(is_valid).to be true
      end
      
      it "handles malformed stored state gracefully" do
        visit_app("ChatOpenAI")
        wait_for_app_load
        
        # Store malformed data
        execute_script("localStorage.setItem('monadicState', 'invalid json {]');")
        
        # Attempt restore
        no_errors = execute_script(<<-JS)
          try {
            window.SessionState.restore();
            return true;
          } catch (error) {
            return false;
          }
        JS
        
        expect(no_errors).to be true
        
        # State should still be valid despite failed restore
        is_valid = execute_script("return window.SessionState.validateState();")
        expect(is_valid).to be true
      end
    end
  end

  describe "Performance and Memory" do
    it "limits stored message history" do
      visit_app("ChatOpenAI")
      wait_for_app_load
      
      # Add many messages
      execute_script(<<-JS)
        for (let i = 0; i < 100; i++) {
          window.SessionState.addMessage({ role: 'user', content: 'Message ' + i });
        }
        window.SessionState.save();
      JS
      
      # Check stored state size
      stored_data = execute_script("return localStorage.getItem('monadicState');")
      stored_state = JSON.parse(stored_data)
      
      # Should only store last 50 messages
      expect(stored_state["conversation"]["messages"].length).to eq(50)
      expect(stored_state["conversation"]["messages"].first["content"]).to include("Message 50")
    end
    
    it "prevents memory leaks from event listeners" do
      visit_app("ChatOpenAI")
      wait_for_app_load
      
      # Add and remove many listeners
      execute_script(<<-JS)
        const callbacks = [];
        for (let i = 0; i < 100; i++) {
          const cb = function() { console.log('Event ' + i); };
          callbacks.push(cb);
          window.SessionState.on('test:event', cb);
        }
        
        // Remove all listeners
        callbacks.forEach(cb => window.SessionState.off('test:event', cb));
      JS
      
      # Check that listeners were properly removed
      listener_count = execute_script(<<-JS)
        const listeners = window.SessionState.listeners.get('test:event');
        return listeners ? listeners.length : 0;
      JS
      
      expect(listener_count).to eq(0)
    end
  end
end