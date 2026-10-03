# frozen_string_literal: true

require "json"
require "open3"
require_relative "environment"

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
        # Read directly; a missing file is a SystemCallError like any other.
        line = File.read(path).each_line.map(&:strip).reverse.find { |l| l.start_with?("#{key}=") }
        return nil unless line

        value = line.split("=", 2).last.to_s.strip.gsub(/\A['"]|['"]\z/, "")
        return nil if value.empty?

        resolve(key, value)
      rescue SystemCallError
        nil
      end

      # Dotenv copies config/env into ENV, references included. Remove those,
      # so no ENV fallback hands a reference on as a key. Resolved values are
      # not put back: every child process would inherit them.
      def scrub_env!(env = ENV)
        env.to_h.each { |key, value| env.delete(key) if reference?(value) }
      end

      # For tests.
      def reset!
        @resolved = nil
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

        File.read(path).each_line.each_with_object({}) do |line, refs|
          key, value = line.strip.split("=", 2)
          next if key.nil? || value.nil? || key.start_with?("#")

          value = value.strip.gsub(/\A['"]|['"]\z/, "")
          refs[key] = value if reference?(value)
        end
      rescue SystemCallError
        {}
      end

      # One `op inject` call for every reference, so 1Password asks at most
      # once. The template goes in on stdin; nothing is written to disk.
      def read_with_op(refs, op: ENV.fetch("MONADIC_OP_CLI", "op"))
        return {} if refs.empty?

        template = refs.map { |key, ref| "#{key}={{ #{ref} }}\n" }.join
        out, _err, status = Open3.capture3(op, "inject", stdin_data: template)
        return {} unless status.success?

        out.each_line.each_with_object({}) do |line, values|
          key, value = line.chomp.split("=", 2)
          values[key] = value if refs.key?(key) && value && !value.empty?
        end
      rescue SystemCallError
        {}
      end
    end
  end
end
