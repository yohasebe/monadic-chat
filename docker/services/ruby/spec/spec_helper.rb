# frozen_string_literal: true

require 'rspec/mocks'
require 'ostruct'
require 'json'
require 'yaml'
require 'tempfile'

# Define global test constants to avoid redefinition warnings
IN_CONTAINER = false unless defined?(IN_CONTAINER)

# Define MonadicApp module with shared constants for tests
module MonadicApp
  # Define constants only if they aren't already defined
  unless defined?(SHARED_VOL)
    SHARED_VOL = "/monadic/data"
  end
  
  unless defined?(LOCAL_SHARED_VOL)
    LOCAL_SHARED_VOL = File.expand_path(File.join(Dir.home, "monadic", "data"))
  end
  
  # Create a standard tokenizer mock that can be used across tests
  class TokenizerMock
    def self.get_tokens_sequence(text)
      # Simple token counting for testing purposes
      text.split(/\s+/).map { |word| "t_#{word}" }
    end
    
    def count_tokens(text, encoding_name = nil)
      return text.to_s.length < 20 ? 10 : 20 # Simulate different token counts based on length
    end
  end
  
  # Only define TOKENIZER if it's not already defined
  unless defined?(TOKENIZER)
    TOKENIZER = TokenizerMock.new
  end
  
  # Define AI_USER_INITIAL_PROMPT if not already defined
  unless defined?(AI_USER_INITIAL_PROMPT)
    AI_USER_INITIAL_PROMPT = "You are generating a response from the perspective of the human user in an ongoing conversation with an AI assistant."
  end
end

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = ".rspec_status"

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  # Include the mocking framework
  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end
  
  # Clear any shared state between tests
  config.after(:each) do
    # Add any cleanup needed between tests
  end
end
