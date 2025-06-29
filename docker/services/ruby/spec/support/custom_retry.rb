# frozen_string_literal: true

# Custom retry mechanism with clean output
module CustomRetry
  class RetryError < StandardError
    attr_reader :attempt, :max_attempts, :original_error

    def initialize(attempt, max_attempts, original_error)
      @attempt = attempt
      @max_attempts = max_attempts
      @original_error = original_error
      super("Failed after #{attempt} attempts: #{original_error.message}")
    end
  end

  def with_retry(max_attempts: 3, wait: 10, exceptions: nil)
    attempt = 0
    exceptions ||= [StandardError]
    
    begin
      attempt += 1
      yield
    rescue *exceptions => e
      if attempt < max_attempts
        # Clear previous error output
        print "\r\033[K"
        
        # Print clean retry message
        puts "\n" + "─" * 80
        puts "🔄 Retry #{attempt}/#{max_attempts}"
        puts "   Error: #{e.class.name} - #{e.message.lines.first&.strip}"
        puts "   Waiting #{wait} seconds before retry..."
        puts "─" * 80
        
        sleep wait
        retry
      else
        # Final failure
        puts "\n" + "─" * 80
        puts "❌ Failed after #{max_attempts} attempts"
        puts "   Final error: #{e.class.name} - #{e.message}"
        puts "─" * 80
        
        raise RetryError.new(attempt, max_attempts, e)
      end
    end
    
    # Success after retry
    if attempt > 1
      puts "\n" + "─" * 80
      puts "✅ Success after #{attempt} attempts"
      puts "─" * 80
    end
  end
end

# Global variable to track retries
$retry_summary = []

# RSpec integration
RSpec.configure do |config|
  config.include CustomRetry
  
  config.before(:suite) do
    $retry_summary = []
  end
  
  config.after(:each, type: :e2e) do |example|
    if example.metadata[:retried] && example.metadata[:retry_attempts] && example.metadata[:retry_attempts] > 0
      $retry_summary << {
        description: example.full_description,
        location: example.location,
        attempts: example.metadata[:retry_attempts],
        status: example.exception ? :failed : :passed
      }
    end
  end
  
  config.after(:suite) do
    if $retry_summary && $retry_summary.any?
      puts "\n\n" + "=" * 80
      puts "RETRY SUMMARY"
      puts "=" * 80
      
      $retry_summary.group_by { |r| r[:status] }.each do |status, results|
        puts "\n#{status == :passed ? '✅ Passed' : '❌ Failed'} after retries:"
        results.each do |result|
          puts "  - #{result[:description]}"
          puts "    Attempts: #{result[:attempts]}, Location: #{result[:location]}"
        end
      end
      
      puts "=" * 80
    end
  end
end

# Helper for E2E tests
module E2ERetryHelper
  def with_e2e_retry(max_attempts: 3, wait: 10, &block)
    # Mark this example as potentially retried
    RSpec.current_example.metadata[:retried] = true
    RSpec.current_example.metadata[:retry_attempts] = 0
    
    with_retry(
      max_attempts: max_attempts,
      wait: wait,
      exceptions: [
        RuntimeError,
        Net::ReadTimeout,
        Net::OpenTimeout,
        Errno::ECONNREFUSED,
        Errno::ETIMEDOUT,
        JSON::ParserError,
        RSpec::Expectations::ExpectationNotMetError
      ]
    ) do
      RSpec.current_example.metadata[:retry_attempts] += 1
      block.call
    end
  rescue CustomRetry::RetryError => e
    # Re-raise the original error for RSpec
    raise e.original_error
  end
end