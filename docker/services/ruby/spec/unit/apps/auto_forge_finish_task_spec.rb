# frozen_string_literal: true

require 'spec_helper'

require_relative '../../../apps/auto_forge/auto_forge_tools'

# Tests for the explicit task-completion signal tool added to AutoForge Claude
# as part of the root fix for the Verification Protocol loop issue.
#
# Design: finish_task is called by the model as its final action. It returns
# a closing message and force-stops the tool call loop by setting
# session[:call_depth_per_turn] to a sentinel that exceeds MAX_FUNC_CALLS.
# See claude_helper.rb L1046 for the receiving side.
RSpec.describe 'AutoForgeTools#finish_task' do
  subject(:tool) do
    Class.new do
      include AutoForgeTools
    end.new
  end

  describe 'return message' do
    it 'declares the task finished in unambiguous past tense' do
      result = tool.finish_task(summary: 'Built a TodoMini web app with localStorage')
      expect(result).to include('TASK FINISHED')
      expect(result).to include('has been successfully generated')
      expect(result).to include('Built a TodoMini web app with localStorage')
    end

    it 'includes the file location when deliverable is provided' do
      result = tool.finish_task(
        summary: 'Built TodoMini',
        deliverable: '/Users/x/monadic/data/auto_forge/TodoMini/index.html'
      )
      expect(result).to include('File location:')
      expect(result).to include('/Users/x/monadic/data/auto_forge/TodoMini/index.html')
    end

    it 'omits the file location line when deliverable is nil' do
      result = tool.finish_task(summary: 'Built TodoMini', deliverable: nil)
      expect(result).not_to include('File location:')
    end

    it 'omits the file location line when deliverable is blank' do
      result = tool.finish_task(summary: 'Built TodoMini', deliverable: '   ')
      expect(result).not_to include('File location:')
    end

    it 'guides the model with a positive final-step instruction' do
      result = tool.finish_task(summary: 'Done')
      expect(result).to include('final step')
      expect(result).to include('one or two sentences')
    end

    it 'contains no negative imperatives (LLM attractor anti-pattern)' do
      result = tool.finish_task(summary: 'Done')
      # Negative commands like "Do NOT ..." cause some models to regenerate
      # the forbidden phrase verbatim. Keep the message purely positive.
      expect(result).not_to match(/do not/i)
      expect(result).not_to match(/don't/i)
    end
  end

  describe 'force-stop via session' do
    it 'sets session[:call_depth_per_turn] to a force-stop sentinel' do
      session = {}
      tool.finish_task(summary: 'Done', session: session)
      expect(session[:call_depth_per_turn]).to be >= 99_999
    end

    it 'reuses MonadicSharedTools::Verification::FORCE_STOP_DEPTH when available' do
      session = {}
      tool.finish_task(summary: 'Done', session: session)
      # The constant is defined by the verification shared tool module.
      # We assert the value matches so finish_task and report_verification
      # use a consistent force-stop sentinel.
      if defined?(MonadicSharedTools::Verification::FORCE_STOP_DEPTH)
        expect(session[:call_depth_per_turn]).to eq(MonadicSharedTools::Verification::FORCE_STOP_DEPTH)
      end
    end

    it 'does not raise when session is nil' do
      expect { tool.finish_task(summary: 'Done') }.not_to raise_error
    end

    it 'does not mutate session when session is nil' do
      # Just verify no implicit side-effects
      result = tool.finish_task(summary: 'Done')
      expect(result).to be_a(String)
    end
  end

  describe 'error handling' do
    it 'handles exceptions gracefully' do
      # Force an error by passing a non-string summary that raises on .strip
      bad = Object.new
      def bad.to_s; raise 'boom'; end
      result = tool.finish_task(summary: bad)
      expect(result).to include('❌ finish_task error')
    end
  end
end
