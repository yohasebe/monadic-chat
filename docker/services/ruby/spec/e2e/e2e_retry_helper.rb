# frozen_string_literal: true

# E2E test retry wrapper
# This module provides a clean way to wrap existing tests with retry functionality
module E2ERetryWrapper
  # Wrap an existing test with retry functionality
  # Usage: 
  #   it "does something" do
  #     with_clean_retry do
  #       # existing test code
  #     end
  #   end
  def with_clean_retry(max_attempts: 3, wait: 10, &block)
    if ENV['USE_CUSTOM_RETRY'] == 'true'
      with_e2e_retry(&block)
    else
      # Fallback to normal execution without retry
      block.call
    end
  end
end

# Include in E2E specs
RSpec.configure do |config|
  config.include E2ERetryWrapper, type: :e2e
end