# frozen_string_literal: true

require 'json'
require 'fileutils'
require 'securerandom'
require_relative 'path_config'

module AutoForge
  module Utils
    module StateManager
      extend self
      include PathConfig

      class StateError < StandardError; end
      class LockError < StateError; end

      # Initialize storage on first access
      def states
        @states ||= {}
      end

      def mutex
        @mutex ||= Mutex.new
      end

      # Simple state structure
      class ProjectState
        attr_reader :project_id, :created_at
        attr_accessor :locks, :history, :artifacts, :metadata, :execution_count

        def initialize(project_id)
          @project_id = project_id
          @created_at = Time.now
          @locks = {}
          @history = []
          @artifacts = {}
          @metadata = {}
          @execution_count = 0
          @lock_mutex = Mutex.new
        end

        def can_execute?
          @execution_count == 0
        end

        def mark_executed!
          @execution_count += 1
        end

        def reset_execution!
          @execution_count = 0
          @artifacts.clear
        end
      end

      # Initialize project
      def init_project(project_id, metadata = {})
        mutex.synchronize do
          return { success: false, message: "Already initialized" } if states[project_id]

          state = ProjectState.new(project_id)
          state.metadata = metadata
          states[project_id] = state

          { success: true, project_id: project_id }
        end
      end

      # Check if can execute main generation
      def can_execute?(project_id)
        state = get_state(project_id)
        return false unless state
        state.can_execute?
      end

      # Mark project as executed
      def mark_executed!(project_id)
        state = get_state(project_id)
        raise StateError, "Project not initialized" unless state

        state.mark_executed!
        log_execution(project_id, { action: "main_execution", result: "started" })
      end

      # Reset execution state for modifications
      def reset_execution(project_id)
        state = get_state(project_id)
        return false unless state

        state.reset_execution!
        log_execution(project_id, { action: "reset_for_modification", result: "ready" })
        true
      end

      # Record generated artifact
      def record_artifact(project_id, path, metadata = {})
        state = get_state(project_id)
        raise StateError, "Project not initialized" unless state

        mutex.synchronize do
          state.artifacts[path] = {
            created_at: Time.now,
            metadata: metadata
          }
        end

        { success: true, path: path }
      end

      # Check if already generated
      def already_generated?(project_id, path)
        state = get_state(project_id)
        return false unless state
        state.artifacts.key?(path)
      end

      # Log execution
      def log_execution(project_id, info)
        state = get_state(project_id)
        return unless state

        mutex.synchronize do
          state.history << { timestamp: Time.now, **info }
        end
      end

      # Get project state
      def get_project_state(project_id)
        state = get_state(project_id)
        return nil unless state

        {
          project_id: state.project_id,
          created_at: state.created_at,
          artifacts: state.artifacts.keys,
          metadata: state.metadata,
          execution_count: state.execution_count
        }
      end

      # Clear project
      def clear_project(project_id)
        mutex.synchronize { states.delete(project_id) }
      end

      private

      def get_state(project_id)
        states[project_id]
      end
    end
  end
end

# Inline tests
if __FILE__ == $0
  require 'minitest/autorun'

  class StateManagerTest < Minitest::Test
    include AutoForge::Utils::StateManager

    def setup
      @project_id = "test_#{Time.now.to_i}"
      clear_project(@project_id)
    end

    def teardown
      clear_project(@project_id)
    end

    def test_single_execution
      init_project(@project_id)

      # First check - can execute
      assert can_execute?(@project_id)

      # Mark as executed
      mark_executed!(@project_id)

      # Second check - cannot execute
      refute can_execute?(@project_id)
    end

    def test_artifact_tracking
      init_project(@project_id)

      # Record artifact
      record_artifact(@project_id, "index.html")

      # Check existence
      assert already_generated?(@project_id, "index.html")
      refute already_generated?(@project_id, "other.html")
    end
  end

  puts "\n=== Running StateManager Tests ==="
end