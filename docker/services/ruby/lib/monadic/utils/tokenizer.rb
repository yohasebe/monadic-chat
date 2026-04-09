# frozen_string_literal: true

require "tiktoken_ruby"

# Native Ruby tokenizer using tiktoken_ruby (Rust binding).
# Drop-in replacement for the former FlaskAppClient that called
# Python tiktoken via HTTP.  The public API is kept identical so
# that callers (streaming_handler, pdf_text_extractor, etc.) need
# no changes.
class Tokenizer
  DEFAULT_ENCODING = "o200k_base"

  def initialize(model_name = nil)
    @model_name = model_name
    # Eagerly cache the most common encoding
    get_cached_encoding(DEFAULT_ENCODING)
  end

  # Always available — no external service dependency
  def service_available?
    true
  end

  # ── Encoding name lookup ──────────────────────────────────────

  def get_encoding_name(model = nil)
    model_name = model || @model_name
    return nil if model_name.nil?

    begin
      enc = Tiktoken.encoding_for_model(model_name)
      enc.name
    rescue StandardError
      nil
    end
  end

  # ── Token counting (with LRU cache) ──────────────────────────

  @@token_count_cache = {}
  @@cache_mutex = Mutex.new
  MAX_CACHE_SIZE = 1000

  def count_tokens(text, encoding_name = DEFAULT_ENCODING)
    text = text.to_s if text.nil? || !text.is_a?(String)

    cache_key = "#{encoding_name}:#{text.hash}"

    @@cache_mutex.synchronize do
      return @@token_count_cache[cache_key] if @@token_count_cache.key?(cache_key)
    end

    enc = get_cached_encoding(encoding_name)
    result = enc.encode(text).length

    @@cache_mutex.synchronize do
      @@token_count_cache.shift if @@token_count_cache.size >= MAX_CACHE_SIZE
      @@token_count_cache[cache_key] = result
    end

    result
  end

  # ── Token sequence / decode ──────────────────────────────────

  def get_tokens_sequence(text)
    text = text.to_s if text.nil? || !text.is_a?(String)

    enc = encoding_for_current_model
    enc.encode(text)
  end

  def decode_tokens(tokens)
    enc = encoding_for_current_model
    enc.decode(tokens)
  rescue StandardError => e
    puts "[Tokenizer] Decode error: #{e.message}"
    nil
  end

  private

  # Cache Tiktoken::Encoding objects to avoid repeated BPE file loading.
  @@encoding_cache = {}
  @@encoding_cache_mutex = Mutex.new

  def get_cached_encoding(encoding_name)
    @@encoding_cache_mutex.synchronize do
      @@encoding_cache[encoding_name] ||= Tiktoken.get_encoding(encoding_name)
    end
  end

  def encoding_for_current_model
    if @model_name
      @@encoding_cache_mutex.synchronize do
        @@encoding_cache[@model_name] ||=
          begin
            Tiktoken.encoding_for_model(@model_name)
          rescue StandardError
            Tiktoken.get_encoding(DEFAULT_ENCODING)
          end
      end
    else
      get_cached_encoding(DEFAULT_ENCODING)
    end
  end
end
