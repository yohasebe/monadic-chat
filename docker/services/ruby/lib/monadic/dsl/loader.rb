# frozen_string_literal: true

require_relative '../utils/shared_path_guard'

module MonadicDSL
  class Loader
    def self.load(file)
      new(file).load
    rescue => e
      # Log the error but continue processing
      app_name = File.basename(file, ".*")
      error_message = "Warning: Failed to load app '#{app_name}' (#{file}): #{e.message}"
      warn error_message

      # Track failed apps in a global array
      $MONADIC_LOADING_ERRORS ||= []
      $MONADIC_LOADING_ERRORS << { app: app_name, file: file, error: e.message }

      nil
    end

    def initialize(file)
      @file = file
      begin
        @content = File.read(file)
      rescue => e
        warn "Warning: Could not read #{file}: #{e.message}"
        raise
      end
    end

    def load
      if dsl_file?
        begin
          load_dsl
        rescue => e
          warn "Warning: Failed to process DSL in #{@file}: #{e.message}"
          load_traditional
        end
      else
        load_traditional
      end
    end

    private

    def dsl_file?
      @content.match?(/^app\s+["']/) ||
        File.extname(@file) == '.mdsl'
    end

    def load_dsl
      # Only handle the simplified DSL format
      app_state = eval(@content, TOPLEVEL_BINDING, @file)

      # Validate MDSL configuration if validator is available
      if defined?(Monadic::Utils::MDSLValidator) && app_state
        begin
          provider = determine_provider(app_state)
          model = app_state.settings[:model] || app_state.settings[:models]&.first

          if provider && model
            validation_result = Monadic::Utils::MDSLValidator.validate_reasoning_parameters(
              app_state.settings,
              provider,
              model
            )

            # Log errors and warnings
            validation_result[:errors].each do |error|
              warn "MDSL Validation Error in #{@file}: #{error}"
            end
            validation_result[:warnings].each do |warning|
              warn "MDSL Validation Warning in #{@file}: #{warning}"
            end
          end
        rescue => e
          warn "MDSL Validation failed for #{@file}: #{e.message}"
        end
      end

      # After creating the class from MDSL, check for and load corresponding files
      base_name = File.basename(@file, '.*')
      dir_path = File.dirname(@file)

      # Remove provider suffix (e.g., _openai, _claude) to get base app name
      app_base_name = base_name.sub(/_\w+$/, '')

      # Load the constants and tools files beside it, if they exist, under
      # the same rule as the app file itself (no link, nothing from outside)
      %w[constants tools].each do |part|
        file = File.join(dir_path, "#{app_base_name}_#{part}.rb")
        next unless File.exist?(file) || File.symlink?(file)

        if Monadic::Utils::SharedPathGuard.code_file?(file, dir_path)
          require file
        else
          warn "Warning: Not loading #{File.basename(file)}: a link, or not a plain file in the app folder"
        end
      end

      app_state
    rescue => e
      warn "Warning: Failed to evaluate DSL in #{@file}: #{e.message}"
      raise
    end

    def load_traditional
      require @file
    rescue => e
      warn "Warning: Failed to require #{@file}: #{e.message}"
      raise
    end

    def determine_provider(app_state)
      # Determine provider from app_state
      if app_state.respond_to?(:settings)
        provider = app_state.settings[:provider]
        return provider if provider

        # Try to infer from group
        group = app_state.settings[:group] if app_state.respond_to?(:settings)
        case group
        when /OpenAI/i then 'OpenAI'
        when /Anthropic|Claude/i then 'Anthropic'
        when /Google|Gemini/i then 'Google'
        when /xAI|Grok/i then 'xAI'
        when /DeepSeek/i then 'DeepSeek'
        when /Mistral/i then 'Mistral'
        when /Cohere/i then 'Cohere'
        end
      end
    end
  end
end
