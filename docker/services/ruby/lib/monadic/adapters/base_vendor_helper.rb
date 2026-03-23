# frozen_string_literal: true

# BaseVendorHelper
# Shared utilities for vendor helpers. Provides macros for common patterns
# (timeouts, model cache) to reduce boilerplate across providers.
# Each vendor helper can adopt these incrementally without changing behavior.

module BaseVendorHelper
  DEFAULT_MAX_RETRIES = 5
  DEFAULT_RETRY_DELAY = 1 # seconds

  def self.included(base)
    base.extend(ClassMethods)
  end

  module ClassMethods
    # Generates timeout class methods and instance methods for a vendor.
    # Each method reads from CONFIG with a fallback to the specified default.
    #
    # Usage:
    #   module OpenAIHelper
    #     include BaseVendorHelper
    #     define_timeouts "OPENAI", open: 20, read: 600, write: 120
    #   end
    #
    # This creates:
    #   - OpenAIHelper.open_timeout  (class method, reads CONFIG["OPENAI_OPEN_TIMEOUT"])
    #   - instance.open_timeout      (delegates to class method)
    #   - Same for read_timeout and write_timeout
    def define_timeouts(prefix, open: 10, read: 600, write: 120)
      vendor_mod = self

      { open_timeout: [open, "OPEN"], read_timeout: [read, "READ"], write_timeout: [write, "WRITE"] }.each do |method_name, (default_val, suffix)|
        config_key = "#{prefix}_#{suffix}_TIMEOUT"

        define_singleton_method(method_name) do
          defined?(CONFIG) ? (CONFIG[config_key]&.to_i || default_val) : default_val
        end

        define_method(method_name) do
          vendor_mod.public_send(method_name)
        end
      end
    end

    # Generates a clear_models_cache method for the given cache key.
    #
    # Usage:
    #   module OpenAIHelper
    #     include BaseVendorHelper
    #     define_models_cache :openai
    #   end
    #
    # This creates:
    #   - instance.clear_models_cache  (sets $MODELS[:openai] = nil)
    def define_models_cache(cache_key)
      define_method(:clear_models_cache) do
        $MODELS[cache_key] = nil
      end
    end
  end

  # Strip base64 image data from inactive session messages to prevent
  # unbounded session growth.  Keeps filenames/titles so auto-attach
  # (fetch_last_images_from_session) can still locate files on disk.
  # Idempotent — safe to call on every request.
  def strip_inactive_image_data(session)
    return unless session[:messages].is_a?(Array)

    session[:messages].each do |msg|
      next if msg.nil? || msg["active"]

      # "images" array (Gemini image gen, user uploads)
      if msg["images"].is_a?(Array)
        msg["images"].each do |img|
          next unless img.is_a?(Hash)
          if img["data"].is_a?(String) && img["data"].start_with?("data:")
            img["data"] = "[stripped]"
          end
        end
      end

      # "content" array — OpenAI multimodal format
      if msg["content"].is_a?(Array)
        msg["content"].each do |part|
          next unless part.is_a?(Hash)
          if part["type"] == "image_url" && part.dig("image_url", "url")&.start_with?("data:")
            part["image_url"]["url"] = "[stripped]"
          end
        end
      end
    end
  end

  # Generic backoff wrapper. Yields a block and retries on common transient
  # network errors. The caller remains responsible for logging.
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
