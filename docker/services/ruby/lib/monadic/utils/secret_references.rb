# frozen_string_literal: true

require "json"
require "open3"
require "securerandom"
require_relative "environment"
require_relative 'env_file'

module Monadic
  module Utils
    # Values in config/env may be written as 1Password references
    # (`OPENAI_API_KEY=op://Vault/Item/field`) instead of the secret itself.
    #
    # Inside the container there is no op CLI: the desktop app reads the
    # references on the host and streams the results into the tmpfs at
    # DELIVERED_PATH (see entrypoint.sh). When the server runs on the host
    # (development mode) it reads them itself, in one `op inject` call.
    #
    # A reference that could not be read leaves its key unset. The reference
    # text is never returned as the value: it would be sent to a provider as
    # an API key, carrying the vault and item names with it. Nothing here
    # prints a resolved value or the reference text; only key names.
    module SecretReferences
      module_function

      REFERENCE = %r{\Aop://}
      # Names of settings and environment variables that hold credentials:
      # the one rule for removing them from child environments and for
      # collecting the values SecretRedactor replaces.
      CREDENTIAL_NAME = /(?:API_KEY|ACCESS_KEY|ACCESS_KEY_ID|_KEY|TOKEN|SECRET|PASSWORD|PASSWD|CREDENTIALS?)\z/i
      DELIVERED_PATH = "/run/monadic-secrets/env"

      def reference?(value)
        value.is_a?(String) && value.match?(REFERENCE)
      end

      # The value to use for key: the value itself, or for a reference the
      # resolved value, or nil when it could not be resolved.
      def resolve(key, value)
        return value unless reference?(value)

        resolved[key]
      end

      # The CONFIG value for a config/env entry, written out or read from
      # 1Password: "true"/"false" and whole numbers become booleans and
      # numbers, which the settings that take them compare against. A
      # credential stays the string it is (a password may be all digits).
      # The whole value must match, so a value that spans lines stays a string.
      def setting_value(key, value)
        return value if key.to_s.match?(CREDENTIAL_NAME)

        case value
        when "true" then true
        when "false" then false
        when /\A\d+\z/ then value.to_i
        when /\A\d+\.\d+\z/ then value.to_f
        else value
        end
      end

      # Keys whose references could not be resolved, for messages.
      def unresolved_keys(pairs)
        pairs.select { |key, value| reference?(value) && resolved[key].nil? }.map(&:first)
      end

      def resolved
        @resolved ||= Environment.in_container? ? read_delivered : read_with_op(references_in_env)
      end

      # One key from config/env, resolved, for scripts that read the file
      # themselves instead of loading CONFIG. nil when absent or unresolved.
      def config_value(key, path = Environment.env_path)
        # The same parse as the server's (EnvFile); a missing file reads as
        # nothing.
        value = EnvFile.parse(path)[key].to_s
        return nil if value.empty?

        resolve(key, value)
      rescue SystemCallError
        nil
      end

      # Dotenv copies config/env into ENV, references included. Remove those,
      # so no ENV fallback hands a reference on as a key. Credentials whose
      # ENV value is the one in the file (`loaded`, the parsed file) are
      # removed too: CONFIG holds them, and every child process would inherit
      # them from ENV. That includes values the rake task loaded before the
      # server started. A credential with another value (set by the shell) is
      # left alone. Resolved values are not put back. The removed credentials
      # are kept in this process (removed_credentials) so SecretRedactor still
      # knows them: Dotenv expands `${VAR}`, so its value can differ from the
      # one in CONFIG.
      def scrub_env!(env = ENV, loaded: {})
        removed = {}
        env.to_h.each do |key, value|
          from_file = loaded.key?(key) && loaded[key] == value && key.match?(CREDENTIAL_NAME)
          removed[key] = value if from_file
          env.delete(key) if reference?(value) || from_file
        end
        @removed_credentials = removed_credentials.merge(removed).freeze
      end

      # Credentials scrub_env! took out of ENV, for SecretRedactor only.
      def removed_credentials
        @removed_credentials || {}
      end

      # Keys whose references could not be read when config/env was loaded,
      # for telling the user which ones (names only).
      def unresolved_at_load
        @unresolved_at_load || []
      end

      def record_unresolved(keys)
        @unresolved_at_load = Array(keys).map(&:to_s).uniq.freeze
      end

      # For tests.
      def reset!
        @resolved = nil
        @unresolved_at_load = nil
        @removed_credentials = nil
      end

      def read_delivered(path = DELIVERED_PATH)
        return {} unless File.file?(path)

        data = JSON.parse(File.read(path))
        data.is_a?(Hash) ? data.select { |k, v| k.is_a?(String) && v.is_a?(String) && !v.empty? } : {}
      rescue JSON::ParserError, SystemCallError
        {}
      end

      def references_in_env(path = Environment.env_path)
        return {} unless File.file?(path)

        EnvFile.parse(path).select { |_key, value| reference?(value) }
      rescue SystemCallError
        {}
      end

      # One `op inject` call for every reference, so 1Password asks at most
      # once. The template goes in on stdin; nothing is written to disk. Each
      # value sits between two copies of a random boundary, so a value that
      # spans lines is kept whole.
      def read_with_op(refs, op: ENV.fetch("MONADIC_OP_CLI", "op"))
        return {} if refs.empty?

        boundary = "--monadic-#{SecureRandom.hex(16)}--"
        template = refs.map { |key, ref| "#{boundary}#{key}\n{{ #{ref} }}\n" }.join + boundary
        out, _err, status = Open3.capture3(op, "inject", stdin_data: template)
        return {} unless status.success?

        out.split(boundary).each_with_object({}) do |part, values|
          key, value = part.split("\n", 2)
          next if key.nil? || value.nil?

          # Only the newline the template put after the value comes off.
          value = value.delete_suffix("\n")
          values[key] = value if refs.key?(key) && !value.empty?
        end
      rescue SystemCallError
        {}
      end
    end
  end
end
