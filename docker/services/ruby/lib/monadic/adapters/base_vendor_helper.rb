# frozen_string_literal: true

# BaseVendorHelper
# Minimal shared utilities for vendor helpers. This module is intentionally
# small and safe; it can be gradually adopted by vendor-specific helpers
# without changing existing behavior.

module BaseVendorHelper
  DEFAULT_MAX_RETRIES = 5
  DEFAULT_RETRY_DELAY = 1 # seconds

  # Generic backoff wrapper. Yields a block and retries on common transient
  # network errors. The caller remains responsible for logging.
  # This method is provided for future use; introducing it does not change
  # existing behavior unless explicitly called from vendor helpers.
  def retry_with_backoff(max_retries: DEFAULT_MAX_RETRIES, delay: DEFAULT_RETRY_DELAY)
    attempts = 0
    begin
      return yield
    rescue HTTP::Error, HTTP::TimeoutError => e
      attempts += 1
      raise e if attempts > max_retries
      sleep(delay)
      retry
    rescue StandardError => e
      # Non-network errors are re-raised immediately; helpers already have
      # their own handling and we do not want to change behavior here.
      raise e
    end
  end
end

