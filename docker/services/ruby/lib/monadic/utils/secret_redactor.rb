# frozen_string_literal: true

require "json"
require "uri"
require_relative "secret_references"

module Monadic
  module Utils
    # Replaces secrets in text that leaves the server process.
    #
    # Two levels:
    # - `redact` (diagnostics: logs, the command log, stdout, error text) replaces
    #   the known secret values, 1Password references, key formats a provider
    #   may echo back, and credential values in headers and URLs.
    # - `redact_values` / `redact_deep` (data that must stay exact, such as MCP
    #   results) replace only the known secret values and 1Password references,
    #   so code, URLs and file contents are otherwise unchanged.
    #
    # Known secret values are the values of settings and environment variables
    # whose names end in API_KEY, TOKEN, SECRET or PASSWORD. CONFIG holds the
    # values resolved from 1Password references, so those are matched too.
    #
    # Account identifiers (organization, project, request ids) are left to
    # ErrorFormatter.scrub_identifiers, which also calls `redact`.
    module SecretRedactor
      module_function

      REDACTION = "[redacted]"
      SENSITIVE_NAME = Monadic::Utils::SecretReferences::CREDENTIAL_NAME
      # Shorter values are not matched: they would replace ordinary words.
      MIN_SECRET_LENGTH = 8

      OP_REFERENCE = %r{\bop://[^\s"'<>]+}

      # Diagnostic patterns only (see `redact`).
      PATTERNS = [
        OP_REFERENCE,
        # Digest credentials are a list of key="value" pairs: the rest of the line goes.
        /\b(?:proxy-)?authorization["']?\s*(?:=>|:|=)\s*["']?Digest[ \t]+\K[^\r\n]+/i,
        /\b(?:x-api-key|x-goog-api-key|authorization|proxy-authorization)["']?\s*(?:=>|:|=)\s*["']?(?:(?:Bearer|Basic|Token|Bot|ApiKey|Key)[ \t]+)?+\K[^\s"'<>;,}\]\[]+/i,
        /[?&](?:key|api_key|access_token|token|password|passwd|secret)=\K[^\s&#"'<>\\)\]}\[]+/i,
        # user:password@ in a URL
        %r{\b[a-z][a-z0-9+.-]*://[^\s/?#:@"'<>]+:\K[^\s/?#@"'<>]+(?=@)}i,
        /\b(?:Bearer|Basic|Token)[ \t]+\K[A-Za-z0-9._~+\/-]{16,}=*/i,
        /\bAIza[A-Za-z0-9_-]{16,}/,
        /\bsk[-_][A-Za-z0-9_-]{16,}/,
        /\bxai-[A-Za-z0-9_-]{16,}/,
        /\bgsk_[A-Za-z0-9]{16,}/,
        /\btvly-[A-Za-z0-9_-]{16,}/,
        /\bya29\.[A-Za-z0-9_-]{20,}/
      ].freeze

      # For diagnostics: known values, references and key formats.
      def redact(text, values = nil)
        return text if text.nil?

        s = redact_values(text, values)
        # Diagnostic text only: invalid bytes are replaced so the patterns can run.
        s = s.dup.force_encoding(Encoding::UTF_8) if s.encoding == Encoding::BINARY
        s = s.scrub("?") unless s.valid_encoding?
        PATTERNS.reduce(s) { |acc, re| acc.gsub(re, REDACTION) }
      rescue StandardError
        # Never let redaction break the caller; drop the text instead of
        # passing it through unredacted.
        REDACTION
      end

      # For exact data: only the known secret values and 1Password references.
      def redact_values(text, values = nil)
        return text if text.nil?

        s = text.to_s
        return s if s.empty?

        values ||= secret_values
        # Output that is not valid text (binary data, broken encodings) is
        # matched as bytes, so it is kept rather than dropped.
        return redact_bytes(s, values) unless s.valid_encoding? && s.encoding != Encoding::BINARY

        values.each { |v| s = s.gsub(v, REDACTION) if s.include?(v) }
        s.gsub(OP_REFERENCE, REDACTION)
      rescue StandardError
        REDACTION
      end

      OP_REFERENCE_BYTES = Regexp.new('op://[^\s"\'<>]+'.b, Regexp::NOENCODING)

      # The value as is, inside JSON (as Ruby writes it and with \uXXXX for
      # non-ASCII, as Python's json.dumps does), in Ruby's inspect output, and
      # percent-encoded (spaces as + or %20, hex digits in either case).
      def encoded_forms(val)
        forms = [val, JSON.generate(val)[1..-2], JSON.generate(val, ascii_only: true)[1..-2], val.inspect[1..-2]]
        form = URI.encode_www_form_component(val)
        percent = form.gsub("+", "%20")
        forms.concat([form, percent, form.gsub(/%[0-9A-F]{2}/, &:downcase), percent.gsub(/%[0-9A-F]{2}/, &:downcase)])
        ascii = JSON.generate(val, ascii_only: true)[1..-2]
        forms << ascii.gsub(/\\u[0-9a-f]{4}/) { |m| m.upcase.sub("\\U", "\\u") }
        forms.uniq
      rescue StandardError
        [val]
      end

      def redact_bytes(s, values)
        encoding = s.encoding
        b = s.b
        values.each do |v|
          vb = v.b
          b = b.gsub(vb, REDACTION.b) if b.include?(vb)
        end
        b.gsub(OP_REFERENCE_BYTES, REDACTION.b).force_encoding(encoding)
      end

      # `redact_values` over every string in a Hash/Array structure, keys
      # included. The secret values are read once for the whole structure.
      def redact_deep(value, values = nil)
        values ||= secret_values
        case value
        when String then redact_values(value, values)
        when Symbol
          redacted = redact_values(value.to_s, values)
          redacted == value.to_s ? value : redacted.to_sym
        when Hash then value.to_h { |k, v| [redact_deep(k, values), redact_deep(v, values)] }
        when Array then value.map { |v| redact_deep(v, values) }
        else value
        end
      end

      # Longest first, so a value that contains another is replaced whole.
      # Each value is also matched in the forms it takes when serialized or
      # encoded (see `encoded_forms`), as in command output, URLs or logs.
      def secret_values
        values = []
        collect = lambda do |source|
          source.each do |k, v|
            next unless k.to_s.match?(SENSITIVE_NAME)

            val = v.to_s
            next if val.length < MIN_SECRET_LENGTH

            values.concat(encoded_forms(val))
          end
        end
        collect.call(CONFIG) if defined?(CONFIG) && CONFIG.respond_to?(:each)
        collect.call(ENV)
        collect.call(Monadic::Utils::SecretReferences.removed_credentials)
        values.uniq.sort_by { |v| -v.length }
      end
    end
  end
end
