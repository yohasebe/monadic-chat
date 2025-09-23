# frozen_string_literal: true

require_relative "environment"
require_relative "setup"

module Monadic
  module Utils
    # Utility helpers to keep PDF storage env config in sync without restarts.
    module PdfStorageConfig
      module_function

      # Reload PDF storage related keys when the env file timestamp changes.
      # @return [Boolean] true when a reload attempt happened due to mtime change.
      def refresh_from_env
        path = Paths::ENV_PATH
        current_mtime = begin
          File.exist?(path) ? File.mtime(path) : nil
        rescue StandardError
          nil
        end
        return false if instance_variable_defined?(:@pdf_env_file_mtime) && @pdf_env_file_mtime == current_mtime

        new_mode = nil
        new_default = nil

        if current_mtime
          begin
            File.foreach(path) do |line|
              stripped = line.strip
              next if stripped.empty? || stripped.start_with?("#")
              key, value = stripped.split("=", 2)
              next unless key && value
              case key
              when "PDF_STORAGE_MODE"
                new_mode = value
              when "PDF_DEFAULT_STORAGE"
                new_default = value
              end
            end
          rescue StandardError
            # Ignore read errors but still record timestamp so we do not loop endlessly.
          end
        end

        apply_config("PDF_STORAGE_MODE", new_mode)
        apply_config("PDF_DEFAULT_STORAGE", new_default)

        @pdf_env_file_mtime = current_mtime
        true
      end

      # Exposed for specs: force next refresh to re-read the env file.
      def reset_tracking!
        remove_instance_variable(:@pdf_env_file_mtime) if instance_variable_defined?(:@pdf_env_file_mtime)
      end

      def apply_config(key, value)
        sanitized = value.is_a?(String) ? value.strip : nil
        sanitized = nil if sanitized && sanitized.empty?
        if sanitized
          CONFIG[key] = sanitized
        else
          CONFIG.delete(key)
        end
      end
      private_class_method :apply_config
    end
  end
end
