# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../lib/monadic/utils/error_pattern_detector'
require_relative '../../../lib/monadic/utils/function_call_error_handler'

RSpec.describe FunctionCallErrorHandler do
  # Test class that includes the module
  class TestFunctionCallErrorHandler
    include FunctionCallErrorHandler
  end
  
  let(:handler) { TestFunctionCallErrorHandler.new }
  let(:session) { {} }
  
  describe '#handle_function_error' do
    context 'with non-error returns' do
      it 'returns false for successful function returns' do
        result = handler.handle_function_error(session, "Success: operation completed", "test_function")
        expect(result).to be false
      end
      
      it 'returns false for nil returns' do
        result = handler.handle_function_error(session, nil, "test_function")
        expect(result).to be false
      end
      
      it 'returns false for empty returns' do
        result = handler.handle_function_error(session, "", "test_function")
        expect(result).to be false
      end
      
      it 'does not modify session for non-errors' do
        handler.handle_function_error(session, "Regular output", "test_function")
        expect(session[:error_patterns]).to be_nil
        expect(session[:parameters]).to be_nil
      end
    end
    
    context 'with error returns' do
      it 'tracks errors that start with ERROR:' do
        handler.handle_function_error(session, "ERROR: Something went wrong", "test_function")
        
        expect(session[:error_patterns]).not_to be_nil
        expect(session[:error_patterns][:history].size).to eq(1)
        expect(session[:error_patterns][:history].first[:error]).to eq("ERROR: Something went wrong")
        expect(session[:error_patterns][:history].first[:function]).to eq("test_function")
      end
      
      it 'returns false for first error occurrence' do
        result = handler.handle_function_error(session, "ERROR: Font family not found", "plot_function")
        expect(result).to be false
      end
      
      it 'returns false for second similar error' do
        handler.handle_function_error(session, "ERROR: findfont: Font family 'Arial' not found", "plot_function")
        result = handler.handle_function_error(session, "ERROR: findfont: Font family 'Helvetica' not found", "plot_function")
        expect(result).to be false
      end
      
      it 'returns true after third similar error' do
        # First error
        handler.handle_function_error(session, "ERROR: findfont: Font family 'Arial' not found", "plot_function")
        # Second error
        handler.handle_function_error(session, "ERROR: findfont: Font family 'Helvetica' not found", "plot_function")
        # Third error should trigger stop
        result = handler.handle_function_error(session, "ERROR: findfont: Font family 'Times' not found", "plot_function")
        
        expect(result).to be true
        expect(session[:parameters]).not_to be_nil
        expect(session[:parameters]["stop_retrying"]).to be true
      end
      
      it 'calls block with suggestion when stopping' do
        received_fragment = nil
        
        # Generate three similar errors
        handler.handle_function_error(session, "ERROR: No module named 'pandas'", "import_function")
        handler.handle_function_error(session, "ERROR: No module named 'numpy'", "import_function")
        handler.handle_function_error(session, "ERROR: No module named 'matplotlib'", "import_function") do |res|
          received_fragment = res
        end
        
        expect(received_fragment).not_to be_nil
        expect(received_fragment["type"]).to eq("fragment")
        expect(received_fragment["content"]).to include("module import errors")
        expect(received_fragment["content"]).to include("pip install")
      end
      
      it 'does not call block if not provided' do
        # Should not raise error when block is not given
        expect {
          handler.handle_function_error(session, "ERROR: Permission denied", "file_function")
          handler.handle_function_error(session, "ERROR: Access denied", "file_function")
          handler.handle_function_error(session, "ERROR: Operation not permitted", "file_function")
        }.not_to raise_error
      end
    end
    
    context 'with different error patterns' do
      it 'resets count when error pattern changes' do
        # Two font errors
        handler.handle_function_error(session, "ERROR: Font not found", "plot1")
        handler.handle_function_error(session, "ERROR: Font family missing", "plot2")
        
        # Different error type - should reset count
        result = handler.handle_function_error(session, "ERROR: Out of memory", "compute")
        expect(result).to be false
        
        # Another memory error
        result = handler.handle_function_error(session, "ERROR: Cannot allocate memory", "compute2")
        expect(result).to be false
      end
      
      it 'tracks multiple different error types separately' do
        # Font error
        handler.handle_function_error(session, "ERROR: Font issue", "plot")
        
        # Module error
        handler.handle_function_error(session, "ERROR: No module named test", "import")
        
        # Back to font error - should not be counted as third occurrence
        result = handler.handle_function_error(session, "ERROR: Font problem again", "plot2")
        expect(result).to be false
      end
    end
  end
  
  describe '#should_stop_for_errors?' do
    it 'returns false when no errors tracked' do
      expect(handler.should_stop_for_errors?(session)).to be_falsey
    end
    
    it 'returns false when stop_retrying is not set' do
      session[:parameters] = { "other_param" => true }
      expect(handler.should_stop_for_errors?(session)).to be_falsey
    end
    
    it 'returns true when stop_retrying is set' do
      session[:parameters] = { "stop_retrying" => true }
      expect(handler.should_stop_for_errors?(session)).to be true
    end
    
    it 'returns false when stop_retrying is explicitly false' do
      session[:parameters] = { "stop_retrying" => false }
      expect(handler.should_stop_for_errors?(session)).to be_falsey
    end
  end
  
  describe '#reset_error_tracking' do
    it 'clears error patterns' do
      # Set up some error tracking
      session[:error_patterns] = {
        history: [{ error: "ERROR: test", timestamp: Time.now, function: "test" }],
        similar_count: 2,
        last_pattern: :font_error
      }
      
      handler.reset_error_tracking(session)
      
      expect(session[:error_patterns]).to be_nil
    end
    
    it 'resets stop_retrying flag if parameters exist' do
      session[:parameters] = { "stop_retrying" => true, "other_param" => "value" }
      
      handler.reset_error_tracking(session)
      
      expect(session[:parameters]["stop_retrying"]).to be false
      expect(session[:parameters]["other_param"]).to eq("value")
    end
    
    it 'handles missing parameters gracefully' do
      expect { handler.reset_error_tracking(session) }.not_to raise_error
    end
  end
  
  describe 'integration with ErrorPatternDetector' do
    it 'properly detects font errors' do
      fragments = []
      
      handler.handle_function_error(session, "ERROR: findfont: Font family 'Arial' not found", "plot1")
      handler.handle_function_error(session, "ERROR: Cannot find font DejaVu Sans", "plot2")
      handler.handle_function_error(session, "ERROR: Font 'Helvetica' not available", "plot3") do |res|
        fragments << res
      end
      
      expect(fragments.size).to eq(1)
      expect(fragments[0]["content"]).to include("font-related errors")
      expect(fragments[0]["content"]).to include("DejaVu Sans")
    end
    
    it 'properly detects module errors' do
      fragments = []
      
      # Use exact module error patterns that will be detected
      handler.handle_function_error(session, "ERROR: No module named pandas", "import1")
      handler.handle_function_error(session, "ERROR: No module named numpy", "import2")
      handler.handle_function_error(session, "ERROR: No module named matplotlib", "import3") do |res|
        fragments << res
      end
      
      expect(fragments.size).to eq(1)
      expect(fragments[0]["content"]).to include("module import errors")
    end
    
    it 'properly detects permission errors' do
      fragments = []
      
      handler.handle_function_error(session, "ERROR: Permission denied: /tmp/file.txt", "write1")
      handler.handle_function_error(session, "ERROR: Permission denied: /var/log", "write2")
      handler.handle_function_error(session, "ERROR: Permission denied when accessing file", "write3") do |res|
        fragments << res
      end
      
      expect(fragments.size).to eq(1)
      expect(fragments[0]["content"]).to include("permission errors")
      expect(fragments[0]["content"]).to include("system configuration")
    end
    
    it 'properly detects resource errors' do
      fragments = []
      
      handler.handle_function_error(session, "ERROR: Out of memory", "compute1")
      handler.handle_function_error(session, "ERROR: Cannot allocate memory for array", "compute2")
      handler.handle_function_error(session, "ERROR: Disk full", "save") do |res|
        fragments << res
      end
      
      expect(fragments.size).to eq(1)
      expect(fragments[0]["content"]).to include("resource errors")
      expect(fragments[0]["content"]).to include("memory/disk space")
    end
    
    it 'properly detects plotting errors' do
      fragments = []
      
      handler.handle_function_error(session, "ERROR: Backend TkAgg is not available", "plot1")
      handler.handle_function_error(session, "ERROR: Failed to create display window", "plot2")
      handler.handle_function_error(session, "ERROR: DISPLAY not set", "plot3") do |res|
        fragments << res
      end
      
      expect(fragments.size).to eq(1)
      expect(fragments[0]["content"]).to include("plotting/visualization errors")
      expect(fragments[0]["content"]).to include("non-interactive backend")
    end
    
    it 'does not trigger stop for unrecognized patterns' do
      fragments = []
      
      # Use truly unrecognized errors that won't match any pattern
      # According to the implementation, these won't trigger stop condition
      result1 = handler.handle_function_error(session, "ERROR: Custom unrecognized error 1", "func1")
      expect(result1).to be false
      
      result2 = handler.handle_function_error(session, "ERROR: Custom unrecognized error 2", "func2")
      expect(result2).to be false
      
      result3 = handler.handle_function_error(session, "ERROR: Custom unrecognized error 3", "func3") do |res|
        fragments << res
      end
      expect(result3).to be false
      
      # No suggestion should be generated for unrecognized patterns
      expect(fragments.size).to eq(0)
    end
  end
  
  describe 'error history management' do
    it 'maintains error history across multiple calls' do
      5.times do |i|
        handler.handle_function_error(session, "ERROR: Test error #{i}", "function_#{i}")
      end
      
      expect(session[:error_patterns][:history].size).to eq(5)
      expect(session[:error_patterns][:history].map { |e| e[:function] }).to eq(%w[function_0 function_1 function_2 function_3 function_4])
    end
    
    it 'limits history to 10 items' do
      15.times do |i|
        handler.handle_function_error(session, "ERROR: Test error #{i}", "function_#{i}")
      end
      
      expect(session[:error_patterns][:history].size).to eq(10)
      # Should have kept the last 10 (5-14)
      expect(session[:error_patterns][:history].first[:function]).to eq("function_5")
      expect(session[:error_patterns][:history].last[:function]).to eq("function_14")
    end
    
    it 'includes timestamp in error history' do
      handler.handle_function_error(session, "ERROR: Test", "test_func")
      
      entry = session[:error_patterns][:history].first
      expect(entry[:timestamp]).to be_a(Time)
      expect(entry[:timestamp]).to be_within(1).of(Time.now)
    end
  end
end