# frozen_string_literal: true

# ProgressBroadcaster Module
# Shared functionality for broadcasting progress messages from various agents
#
# This module provides a common implementation for agents that need to
# show progress during long-running operations via WebSocket or block callbacks.

module Monadic
  module Agents
    module ProgressBroadcaster
      # Broadcast progress message
      # @param app_name [String] Application name for logging
      # @param message [String] Progress message to display
      # @param elapsed_minutes [Integer, nil] Elapsed time in minutes (nil or 0 for initial message)
      # @param i18n_key [String, nil] Optional i18n key for localization
      # @param block [Proc] Optional callback block
      def broadcast_progress(app_name:, message:, elapsed_minutes: nil, i18n_key: nil, &block)
        progress_data = {
          "type" => "wait",
          "content" => message,
          "source" => self.class.name.split('::').last,
          "minutes" => elapsed_minutes || 0
        }

        # Add i18n data if provided
        if i18n_key
          progress_data["i18n"] = { i18n_key => true }
        end

        # Send via block or WebSocketHelper
        send_progress_message(progress_data, &block)
      rescue => e
        if defined?(CONFIG) && CONFIG["EXTRA_LOGGING"]
          puts "[ProgressBroadcaster] Error broadcasting progress: #{e.message}"
        end
      end

      # Send initial progress message
      # @param app_name [String] Application name
      # @param message [String] Optional custom message
      # @param i18n_key [String, nil] Optional i18n key
      # @param block [Proc] Optional callback block
      def send_initial_progress(app_name:, message: nil, i18n_key: nil, &block)
        default_message = "Processing request"
        broadcast_progress(
          app_name: app_name,
          message: message || default_message,
          elapsed_minutes: 0,
          i18n_key: i18n_key,
          &block
        )
      end

      # Force send progress message immediately
      # Use this when you need to ensure a progress message is shown
      # @param message [String] The message to send
      # @param app_name [String] Application name
      # @param i18n_key [String, nil] Optional i18n key for localization
      def force_progress_message(message:, app_name: nil, i18n_key: nil)
        progress_data = {
          "type" => "wait",
          "content" => message,
          "source" => app_name || self.class.name.split('::').last,
          "minutes" => 0
        }

        # Add i18n data if provided
        if i18n_key
          progress_data["i18n"] = { i18n_key => true }
        end

        # Try all available methods to send the message
        if defined?(::WebSocketHelper)
          helper = ::WebSocketHelper
          if helper.respond_to?(:send_progress_fragment)
            session_id = Thread.current[:websocket_session_id]
            helper.send_progress_fragment(progress_data, session_id)

            if defined?(CONFIG) && CONFIG["EXTRA_LOGGING"]
              puts "[ProgressBroadcaster] Forced progress message sent: #{message}"
            end
            return true
          end
        end

        if defined?(CONFIG) && CONFIG["EXTRA_LOGGING"]
          puts "[ProgressBroadcaster] Warning: Could not force send progress message"
        end
        false
      end

      # Execute block with progress tracking
      # @param app_name [String] Application name
      # @param message [String] Progress message
      # @param interval [Integer] Update interval in seconds
      # @param timeout [Integer] Timeout in seconds
      # @param i18n_key [String, nil] Optional i18n key
      # @param progress_callback [Proc] Optional callback for progress updates
      def with_progress_tracking(app_name:, message: nil, interval: 60, timeout: 300, i18n_key: nil, progress_callback: nil)
        progress_thread = nil

        begin
          # Send initial progress message
          send_initial_progress(
            app_name: app_name,
            message: message,
            i18n_key: i18n_key,
            &progress_callback
          )

          # Start progress thread for long operations
          if timeout > 120
            progress_thread = start_progress_thread(
              app_name: app_name,
              message: message,
              interval: interval,
              timeout: timeout,
              i18n_key: i18n_key,
              &progress_callback
            )
          end

          # Execute the main operation
          result = yield

          # Stop progress thread on success
          if progress_thread
            progress_thread[:should_stop] = true
          end

          result
        rescue => e
          # Stop progress thread on error
          if progress_thread
            progress_thread[:should_stop] = true
          end
          raise e
        ensure
          # Clean up progress thread
          cleanup_progress_thread(progress_thread) if progress_thread
        end
      end

      private

      # Send progress message via block or WebSocketHelper
      def send_progress_message(progress_data, &block)
        if block_given?
          # Use block callback (e.g., AutoForge)
          block.call(progress_data)
        elsif defined?(::WebSocketHelper)
          # Use WebSocketHelper for broadcast
          # Note: We don't check EventMachine.reactor_running? here because:
          # 1. WebSocketHelper handles its own EventMachine requirements internally
          # 2. Checking here can cause false negatives in tool execution contexts
          helper = ::WebSocketHelper
          if helper.respond_to?(:send_progress_fragment)
            session_id = Thread.current[:websocket_session_id]

            # WebSocketHelper.send_progress_fragment(fragment, target_session_id = nil)
            # Session ID nil = broadcast to all
            helper.send_progress_fragment(progress_data, session_id)

            if defined?(CONFIG) && CONFIG["EXTRA_LOGGING"]
              if session_id
                puts "[ProgressBroadcaster] Sent progress to session #{session_id}: #{progress_data["content"]}"
              else
                puts "[ProgressBroadcaster] Broadcasting progress to all: #{progress_data["content"]}"
              end
            end
          elsif defined?(CONFIG) && CONFIG["EXTRA_LOGGING"]
            puts "[ProgressBroadcaster] Warning: WebSocketHelper does not respond to send_progress_fragment"
          end
        else
          # Cannot send progress
          if defined?(CONFIG) && CONFIG["EXTRA_LOGGING"]
            puts "[ProgressBroadcaster] Warning: Cannot send progress (no WebSocketHelper)"
          end
        end
      end

      # Start progress tracking thread
      def start_progress_thread(app_name:, message:, interval:, timeout:, i18n_key:, &block)
        # Capture parent thread's session ID
        parent_session_id = Thread.current[:websocket_session_id]

        thread = Thread.new do
          Thread.current.report_on_exception = false
          Thread.current[:app_name] = app_name
          Thread.current[:websocket_session_id] = parent_session_id

          begin
            start_time = Time.now
            last_update = start_time

            while !Thread.current[:should_stop]
              # Sleep in small increments for responsiveness
              (interval * 2).times do
                sleep 0.5
                break if Thread.current[:should_stop]
              end

              break if Thread.current[:should_stop]

              elapsed = Time.now - start_time
              since_last = Time.now - last_update

              if since_last >= interval
                minutes = (elapsed / 60).floor

                # Send progress update
                broadcast_progress(
                  app_name: app_name,
                  message: message || "Processing in progress",
                  elapsed_minutes: minutes,
                  i18n_key: i18n_key,
                  &block
                )

                last_update = Time.now
              end

              # Check timeout
              break if elapsed > timeout
            end
          rescue => e
            # Log thread errors
            if defined?(CONFIG) && CONFIG["EXTRA_LOGGING"]
              puts "[ProgressBroadcaster] Thread error: #{e.message}"
              puts "[ProgressBroadcaster] Backtrace: #{e.backtrace.first(3).join("\n")}"
            end
            Thread.current[:error] = e
          ensure
            Thread.current[:completed] = true
          end
        end

        # Initialize thread control
        thread[:should_stop] = false
        thread[:started_at] = Time.now
        thread
      end

      # Clean up progress thread
      def cleanup_progress_thread(thread)
        return unless thread

        if thread.alive?
          thread[:should_stop] = true

          # Graceful shutdown with timeout
          if thread.join(1)
            if defined?(CONFIG) && CONFIG["EXTRA_LOGGING"]
              puts "[ProgressBroadcaster] Thread stopped gracefully"
            end
          elsif thread.join(1)
            if defined?(CONFIG) && CONFIG["EXTRA_LOGGING"]
              puts "[ProgressBroadcaster] Thread stopped after extended wait"
            end
          else
            # Force kill if necessary
            thread.kill
            if defined?(CONFIG) && CONFIG["EXTRA_LOGGING"]
              puts "[ProgressBroadcaster] Thread force killed"
            end
          end
        end

        # Log any thread errors
        if thread[:error] && defined?(CONFIG) && CONFIG["EXTRA_LOGGING"]
          puts "[ProgressBroadcaster] Thread had error: #{thread[:error].message}"
        end
      rescue => e
        if defined?(CONFIG) && CONFIG["EXTRA_LOGGING"]
          puts "[ProgressBroadcaster] Thread cleanup error: #{e.message}"
        end
      end
    end
  end
end