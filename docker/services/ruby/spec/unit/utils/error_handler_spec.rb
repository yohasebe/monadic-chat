# frozen_string_literal: true

require 'spec_helper'
require 'net/http'
require 'json'
require_relative '../../../lib/monadic/utils/error_handler'
require_relative '../../../lib/monadic/utils/debug_helper'

RSpec.describe ErrorHandler do
  # Test the new unified error formatting methods
  describe 'Unified Error System' do
    describe '.format_error' do
      it 'formats basic error message' do
        result = ErrorHandler.format_error(
          category: :api,
          message: "Request failed"
        )
        expect(result).to eq("Error: [API Error] - Request failed")
      end

      it 'includes suggestion when provided' do
        result = ErrorHandler.format_error(
          category: :validation,
          message: "Invalid input",
          suggestion: "Check your data format"
        )
        expect(result).to eq("Error: [Invalid Input] - Invalid input. Check your data format")
      end

      it 'includes error code when provided' do
        result = ErrorHandler.format_error(
          category: :api,
          message: "Request failed",
          code: "E001"
        )
        expect(result).to eq("Error: [API Error] - Request failed (Code: E001)")
      end
    end

    describe '.format_provider_error' do
      it 'formats provider error with rate limit detection' do
        result = ErrorHandler.format_provider_error(
          provider: "OpenAI",
          error: "Rate limit exceeded"
        )
        expect(result).to include("[Rate Limit]")
        expect(result).to include("OpenAI")
        expect(result).to include("Please wait before retrying")
      end

      it 'formats provider error with authentication detection' do
        result = ErrorHandler.format_provider_error(
          provider: "Claude",
          error: "Unauthorized: Invalid API key"
        )
        expect(result).to include("[Authentication Error]")
        expect(result).to include("Claude")
        expect(result).to include("Check your API key configuration")
      end
    end

    describe '.format_tool_error' do
      it 'formats tool execution error' do
        result = ErrorHandler.format_tool_error(
          tool: "create_jupyter_notebook",
          error: "Permission denied"
        )
        expect(result).to include("[Tool Error]")
        expect(result).to include("create_jupyter_notebook")
        expect(result).to include("Permission denied")
      end
    end

    describe '.format_validation_error' do
      it 'formats required field error' do
        result = ErrorHandler.format_validation_error(
          field: "Filename",
          requirement: "Please provide a valid filename"
        )
        expect(result).to include("[Invalid Input]")
        expect(result).to include("Filename is required")
      end

      it 'formats invalid value error' do
        result = ErrorHandler.format_validation_error(
          field: "Temperature",
          requirement: "Must be between 0 and 1",
          value: "2.5"
        )
        expect(result).to include("[Invalid Input]")
        expect(result).to include("Temperature has invalid value")
      end
    end
  end

  # Test class that includes ErrorHandler for backward compatibility
  class TestErrorHandler
    include ErrorHandler
  end
  
  let(:handler) { TestErrorHandler.new }
  
  describe '#log_error' do
    before do
      allow(DebugHelper).to receive(:debug)
    end
    
    context 'with network errors' do
      it 'logs HTTP timeout errors correctly' do
        error = HTTP::TimeoutError.new("Request timed out")
        context = { url: 'https://api.example.com', method: 'GET' }
        
        handler.log_error(error, context)
        
        expect(DebugHelper).to have_received(:debug).with(
          a_string_matching(/Network error:.*HTTP::TimeoutError/),
          "api",
          level: :error
        )
      end
      
      it 'logs connection refused errors' do
        error = Errno::ECONNREFUSED.new("Connection refused")
        
        handler.log_error(error)
        
        expect(DebugHelper).to have_received(:debug).with(
          a_string_matching(/Network error:.*ECONNREFUSED/),
          "api",
          level: :error
        )
      end
      
      it 'logs network timeout errors' do
        error = Net::ReadTimeout.new("Read timeout")
        
        handler.log_error(error)
        
        expect(DebugHelper).to have_received(:debug).with(
          a_string_matching(/Network error:.*Net::ReadTimeout/),
          "api",
          level: :error
        )
      end
    end
    
    context 'with file system errors' do
      it 'logs file not found errors' do
        error = Errno::ENOENT.new("No such file or directory")
        context = { file_path: '/tmp/missing.txt' }
        
        handler.log_error(error, context)
        
        expect(DebugHelper).to have_received(:debug).with(
          a_string_matching(/File system error:.*ENOENT/),
          "app",
          level: :error
        )
      end
      
      it 'logs permission denied errors' do
        error = Errno::EACCES.new("Permission denied")
        
        handler.log_error(error)
        
        expect(DebugHelper).to have_received(:debug).with(
          a_string_matching(/File system error:.*EACCES/),
          "app",
          level: :error
        )
      end
      
      it 'logs disk space errors' do
        error = Errno::ENOSPC.new("No space left on device")
        
        handler.log_error(error)
        
        expect(DebugHelper).to have_received(:debug).with(
          a_string_matching(/File system error:.*ENOSPC/),
          "app",
          level: :error
        )
      end
    end
    
    context 'with data errors' do
      it 'logs JSON parsing errors as warnings' do
        error = JSON::ParserError.new("unexpected token")
        
        handler.log_error(error)
        
        expect(DebugHelper).to have_received(:debug).with(
          a_string_matching(/Data parsing error:.*JSON::ParserError/),
          "app",
          level: :warning
        )
      end
      
      it 'logs type errors' do
        error = TypeError.new("wrong argument type")
        
        handler.log_error(error)
        
        expect(DebugHelper).to have_received(:debug).with(
          a_string_matching(/Data parsing error:.*TypeError/),
          "app",
          level: :warning
        )
      end
    end
    
    context 'with unexpected errors' do
      it 'logs unknown errors as unexpected' do
        error = StandardError.new("Something went wrong")
        
        handler.log_error(error)
        
        expect(DebugHelper).to have_received(:debug).with(
          a_string_matching(/Unexpected error:.*StandardError/),
          "app",
          level: :error
        )
      end
    end
    
    it 'includes context information in logs' do
      error = StandardError.new("Error with context")
      context = { user_id: 123, action: 'file_upload' }
      
      handler.log_error(error, context)
      
      expect(DebugHelper).to have_received(:debug).with(
        a_string_matching(/"context":\{"user_id":123,"action":"file_upload"\}/),
        "app",
        level: :error
      )
    end
    
    it 'includes limited backtrace in logs' do
      error = StandardError.new("Error with backtrace")
      error.set_backtrace(Array.new(10) { |i| "line #{i}" })
      
      handler.log_error(error)
      
      expect(DebugHelper).to have_received(:debug).with(
        a_string_matching(/"backtrace":\["line 0","line 1","line 2","line 3","line 4"\]/),
        "app",
        level: :error
      )
    end
  end
  
  describe '#handle_error' do
    before do
      allow(DebugHelper).to receive(:debug)
    end
    
    context 'with network errors' do
      it 'returns retry strategy for timeout errors' do
        error = Net::ReadTimeout.new("Read timeout")
        
        result = handler.handle_error(error)
        
        expect(result[:error]).to include("Request timed out")
        expect(result[:retry]).to be true
      end
      
      it 'returns no-retry for connection refused' do
        error = Errno::ECONNREFUSED.new("Connection refused")
        
        result = handler.handle_error(error)
        
        expect(result[:error]).to include("Connection refused")
        expect(result[:retry]).to be false
      end
      
      it 'returns retry for generic network errors' do
        error = HTTP::ConnectionError.new("Connection error")
        
        result = handler.handle_error(error)
        
        expect(result[:error]).to include("Network error occurred")
        expect(result[:retry]).to be true
      end
    end
    
    context 'with file system errors' do
      it 'handles file not found with context' do
        error = Errno::ENOENT.new("No such file")
        context = { file_path: '/tmp/test.txt' }
        
        result = handler.handle_error(error, context)
        
        expect(result[:error]).to eq("File not found: /tmp/test.txt")
        expect(result[:retry]).to be false
      end
      
      it 'handles permission denied with context' do
        error = Errno::EACCES.new("Permission denied")
        context = { file_path: '/root/secret.txt' }
        
        result = handler.handle_error(error, context)
        
        expect(result[:error]).to eq("Permission denied accessing: /root/secret.txt")
        expect(result[:retry]).to be false
      end
      
      it 'handles generic file errors' do
        error = IOError.new("IO operation failed")
        
        result = handler.handle_error(error)
        
        expect(result[:error]).to include("File system error")
        expect(result[:retry]).to be false
      end
    end
    
    context 'with data errors' do
      it 'handles JSON parsing errors with suggestion' do
        error = JSON::ParserError.new("unexpected token")
        
        result = handler.handle_error(error)
        
        expect(result[:error]).to eq("Invalid JSON format")
        expect(result[:retry]).to be false
        expect(result[:suggestion]).to eq("Check the data format")
      end
      
      it 'handles generic data errors' do
        error = ArgumentError.new("wrong number of arguments")
        
        result = handler.handle_error(error)
        
        expect(result[:error]).to include("Data processing error")
        expect(result[:retry]).to be false
      end
    end
    
    context 'with unexpected errors' do
      it 'handles unknown error types' do
        error = RuntimeError.new("Unexpected runtime error")
        
        result = handler.handle_error(error)
        
        expect(result[:error]).to include("An unexpected error occurred")
        expect(result[:retry]).to be false
      end
    end
  end
  
  describe 'error categorization' do
    it 'correctly categorizes all network error types' do
      network_errors = [
        [HTTP::Error, "HTTP error"],
        [HTTP::TimeoutError, "Timeout"],
        [HTTP::ConnectionError, "Connection error"],
        [Net::HTTPError, "404"],
        [Net::OpenTimeout, "Open timeout"],
        [Net::ReadTimeout, "Read timeout"],
        [Errno::ECONNREFUSED, "Connection refused"],
        [Errno::ETIMEDOUT, "Connection timed out"],
        [Errno::ENETUNREACH, "Network unreachable"]
      ]
      
      network_errors.each do |error_class, message|
        # Create fresh handler instance for each test
        fresh_handler = TestErrorHandler.new
        allow(DebugHelper).to receive(:debug)
        
        error = error_class == Net::HTTPError ? 
                error_class.new(message, "Not Found") : 
                error_class.new(message)
        
        fresh_handler.log_error(error)
        
        expect(DebugHelper).to have_received(:debug).with(
          a_string_matching(/Network error:/),
          "api",
          level: :error
        ).at_least(:once)
      end
    end
    
    it 'correctly categorizes all file system error types' do
      file_errors = [
        [Errno::ENOENT, "File not found"],
        [Errno::EACCES, "Permission denied"],
        [Errno::EISDIR, "Is a directory"],
        [Errno::ENOSPC, "No space left"],
        [IOError, "IO error"],
        [SystemCallError, "System call error"]
      ]
      
      file_errors.each do |error_class, message|
        # Create fresh handler instance for each test
        fresh_handler = TestErrorHandler.new
        allow(DebugHelper).to receive(:debug)
        
        error = error_class == SystemCallError ? 
                error_class.new(message, 1) : 
                error_class.new(message)
        
        fresh_handler.log_error(error)
        
        expect(DebugHelper).to have_received(:debug).with(
          a_string_matching(/File system error:/),
          "app",
          level: :error
        ).at_least(:once)
      end
    end
    
    it 'correctly categorizes all data error types' do
      data_errors = [
        [JSON::ParserError, "Parse error"],
        [ArgumentError, "Argument error"],
        [TypeError, "Type error"],
        [NoMethodError, "No method error"]
      ]
      
      data_errors.each do |error_class, message|
        # Create fresh handler instance for each test
        fresh_handler = TestErrorHandler.new
        allow(DebugHelper).to receive(:debug)
        
        error = error_class.new(message)
        
        fresh_handler.log_error(error)
        
        expect(DebugHelper).to have_received(:debug).with(
          a_string_matching(/Data parsing error:/),
          "app",
          level: :warning
        ).at_least(:once)
      end
    end
  end
  
  describe 'edge cases' do
    before do
      allow(DebugHelper).to receive(:debug)
    end
    
    it 'handles errors with nil message' do
      error = StandardError.new(nil)
      
      expect { handler.handle_error(error) }.not_to raise_error
    end
    
    it 'handles errors without backtrace' do
      error = StandardError.new("No backtrace")
      
      expect { handler.log_error(error) }.not_to raise_error
    end
    
    it 'handles empty context' do
      error = StandardError.new("Error")
      
      result = handler.handle_error(error, {})
      
      expect(result).to be_a(Hash)
      expect(result[:error]).not_to be_nil
    end
    
    it 'preserves original error information' do
      original_message = "Original error message"
      error = StandardError.new(original_message)
      
      handler.handle_error(error)
      
      expect(DebugHelper).to have_received(:debug).with(
        a_string_matching(/#{original_message}/),
        "app",
        level: :error
      )
    end
  end
  
  describe 'integration scenarios' do
    before do
      allow(DebugHelper).to receive(:debug)
    end
    
    it 'handles cascading errors gracefully' do
      # First error
      error1 = Net::ReadTimeout.new("Timeout")
      result1 = handler.handle_error(error1)
      expect(result1[:retry]).to be true
      
      # Second error (after retry)
      error2 = Errno::ECONNREFUSED.new("Connection refused")
      result2 = handler.handle_error(error2)
      expect(result2[:retry]).to be false
    end
    
    it 'maintains error context through handling' do
      error = Errno::ENOENT.new("File not found")
      context = { 
        file_path: '/data/input.txt',
        operation: 'read',
        user: 'test_user'
      }
      
      result = handler.handle_error(error, context)
      
      expect(result[:error]).to include(context[:file_path])
      expect(DebugHelper).to have_received(:debug).with(
        a_string_matching(/"operation":"read"/),
        "app",
        level: :error
      )
    end
  end
end