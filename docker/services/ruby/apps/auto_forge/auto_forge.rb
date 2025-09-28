# frozen_string_literal: true

require 'digest'
require 'securerandom'
require 'tempfile'
require 'time'

require_relative 'auto_forge_utils'
require_relative 'utils/state_manager'
require_relative 'utils/prompt_builder'
require_relative 'utils/file_operations'
require_relative 'agents/html_generator'
require_relative '../../lib/monadic/agents/gpt5_codex_agent'

module AutoForge
  class Orchestrator
    include Utils::StateManager
    include Utils::PromptBuilder
    include Utils::FileOperations

    attr_reader :project_id, :project_path

    def initialize(context)
      @context = context
      @project_id = nil
      @project_path = nil
    end

    # Main entry point - single execution only
    def forge_project(spec)
      # Initialize project state
      project_context = resolve_project_context(spec)
      return project_context if project_context[:error]

      @project_id = project_context[:project_id]
      @project_path = project_context[:path]

      unless ensure_state_ready(project_context, spec)
        return { success: false, error: "Failed to prepare project state" }
      end

      mark_executed!(@project_id)

      begin
        log_execution(@project_id, {
          action: "use_directory",
          path: @project_path,
          existing: project_context[:existing]
        })

        # For single HTML experiment, we only generate one file
        result = generate_single_html(spec)

        if result[:success]
          persist_project_context(project_context, spec)

          {
            success: true,
            project_path: @project_path,
            files_created: [result[:file]],
            project_id: @project_id,
            message: "Project successfully generated at #{@project_path}"
          }
        else
          {
            success: false,
            error: result[:error],
            project_path: @project_path,
            project_id: @project_id
          }
        end

      rescue => e
        log_execution(@project_id, {
          action: "error",
          error: e.message,
          backtrace: e.backtrace[0..2]
        })

        {
          success: false,
          error: "Orchestration failed: #{e.message}",
          project_path: @project_path,
          project_id: @project_id
        }
      end
    end

    private

    def resolve_project_context(spec)
      reset_requested = truthy?(value_from_spec(spec, :reset))

      unless reset_requested
        # First try to find existing context from current session
        existing_context = existing_project_context(spec)
        return existing_context if existing_context

        # If no context in session, try to find recent project by name
        spec_name = value_from_spec(spec, :name)
        if spec_name && !spec_name.strip.empty?
          recent_project = AutoForgeUtils.find_recent_project(spec_name)
          if recent_project
            puts "[AutoForge] Found recent project: #{recent_project[:name]} at #{recent_project[:path]}" if CONFIG && CONFIG["EXTRA_LOGGING"]
            return {
              project_id: "project_#{Digest::MD5.hexdigest(recent_project[:path])[0..11]}",
              path: recent_project[:path],
              name: recent_project[:name],
              existing: true
            }
          end
        end
      end

      # Create new project
      project_info = AutoForgeUtils.create_project_directory(
        value_from_spec(spec, :name) || value_from_spec(spec, :type) || 'app'
      )

      {
        project_id: "project_#{SecureRandom.hex(6)}",
        path: project_info[:path],
        name: project_info[:name],
        existing: false
      }
    rescue AutoForgeUtils::ProjectCreationError => e
      { success: false, error: e.message }
    end

    def ensure_state_ready(project_context, metadata)
      state_exists = !!get_project_state(project_context[:project_id])

      unless state_exists
        init_result = init_project(project_context[:project_id], metadata)
        return false unless init_result[:success] || init_result[:message] == "Already initialized"
      end

      reset_execution(project_context[:project_id]) if project_context[:existing]
      true
    end

    def existing_project_context(spec)
      data = fetch_context_data
      puts "[AutoForge] Checking for existing project, context data: #{data.inspect}" if CONFIG && CONFIG["EXTRA_LOGGING"]

      manual_path = value_from_spec(spec, :project_path) || value_from_spec(spec, :project_dir)
      path = manual_path || data[:project_path]

      puts "[AutoForge] Manual path: #{manual_path}, Data path: #{data[:project_path]}, Final path: #{path}" if CONFIG && CONFIG["EXTRA_LOGGING"]

      return nil unless path && !path.to_s.strip.empty?
      return nil unless Dir.exist?(path)

      spec_name = value_from_spec(spec, :name)
      if manual_path.nil? && spec_name && data[:base_name] && !spec_name.to_s.strip.empty?
        matches = spec_name.to_s.strip.casecmp?(data[:base_name].to_s.strip)
        puts "[AutoForge] Name comparison: '#{spec_name}' vs '#{data[:base_name]}' = #{matches}" if CONFIG && CONFIG["EXTRA_LOGGING"]
        return nil unless matches
      end

      project_id = value_from_spec(spec, :project_id) || data[:project_id] || stable_project_id(path)
      {
        project_id: project_id,
        path: path,
        name: data[:project_name] || File.basename(path),
        existing: true
      }
    end

    def fetch_context_data
      return {} unless @context.respond_to?(:[])

      data = @context[:auto_forge] || @context['auto_forge']
      return {} unless data

      data = data.to_h if data.respond_to?(:to_h)
      data = data.transform_keys(&:to_sym) if data.respond_to?(:transform_keys)
      data || {}
    end

    def persist_project_context(project_context, spec)
      return unless @context.respond_to?(:[]=) && @context.respond_to?(:[])

      store = @context[:auto_forge] || @context['auto_forge'] || {}
      store = store.to_h if store.respond_to?(:to_h)
      store = store.transform_keys(&:to_sym) if store.respond_to?(:transform_keys)

      store[:project_id] = @project_id
      store[:project_path] = @project_path
      store[:project_name] = project_context[:name] || value_from_spec(spec, :name)
      store[:base_name] = value_from_spec(spec, :name) || value_from_spec(spec, :type)
      store[:updated_at] = Time.now.iso8601

      if @context.respond_to?(:[]=)
        @context[:auto_forge] = store
      end
    end

    def stable_project_id(path)
      Digest::SHA1.hexdigest(path.to_s)[0, 16].prepend('project_')
    end

    def value_from_spec(spec, key)
      return nil unless spec
      if spec.respond_to?(:[])
        spec[key] || spec[key.to_s]
      end
    end

    def truthy?(value)
      return false if value.nil?
      return value if value == true || value == false
      %w[true 1 yes].include?(value.to_s.strip.downcase)
    end

    # Generate single HTML file with embedded CSS/JS
    def generate_single_html(spec)
      file_name = "index.html"
      file_path = File.join(@project_path, file_name)

      existing_content = File.exist?(file_path) ? File.read(file_path) : nil
      if existing_content
        puts "[AutoForge] Found existing file at #{file_path}, size: #{existing_content.length} bytes" if CONFIG && CONFIG["EXTRA_LOGGING"]
        puts "[AutoForge] Will modify existing content instead of creating new" if CONFIG && CONFIG["EXTRA_LOGGING"]
      else
        puts "[AutoForge] No existing file found at #{file_path}, creating new" if CONFIG && CONFIG["EXTRA_LOGGING"]
      end

      # Build prompt using PromptBuilder with existing content context
      prompt = build_single_html_prompt(spec, existing_content: existing_content, file_name: file_name)

      log_execution(@project_id, {
        action: "generate_file",
        file: file_name,
        prompt_length: prompt.length
      })

      # Call HTML generator agent
      puts "[AutoForge] Creating HTML generator with context" if CONFIG && CONFIG["EXTRA_LOGGING"]
      generator = Agents::HtmlGenerator.new(@context)

      puts "[AutoForge] Calling generator.generate" if CONFIG && CONFIG["EXTRA_LOGGING"]
      generation_result = generator.generate(prompt, existing_content: existing_content, file_name: file_name)

      puts "[AutoForge] Generation result type: #{generation_result.class}, nil?: #{generation_result.nil?}" if CONFIG && CONFIG["EXTRA_LOGGING"]

      if generation_result.nil?
        puts "[AutoForge] Generation result is nil - returning error" if CONFIG && CONFIG["EXTRA_LOGGING"]
        return { success: false, error: "HTML generation failed - GPT-5-Codex unavailable" }
      end

      normalized_result = normalize_generation_result(generation_result)
      puts "[AutoForge] Normalized result: #{normalized_result.inspect[0..200]}" if CONFIG && CONFIG["EXTRA_LOGGING"]

      case normalized_result
      in { mode: :error, error: error_msg, details: details }
        puts "[AutoForge] Generation failed with error: #{error_msg}" if CONFIG && CONFIG["EXTRA_LOGGING"]
        puts "[AutoForge] Error details: #{details.inspect}" if CONFIG && CONFIG["EXTRA_LOGGING"] && details
        return { success: false, error: error_msg, details: details }
      in { mode: :patch, patch: patch_text }
        puts "[AutoForge] Applying patch to file" if CONFIG && CONFIG["EXTRA_LOGGING"]
        apply_patch_to_file(file_path, patch_text)
      in { mode: :full, content: content }
        puts "[AutoForge] Writing full file, content length: #{content.length}" if CONFIG && CONFIG["EXTRA_LOGGING"]
        write_full_file(file_path, content)
      else
        puts "[AutoForge] Generator returned empty content - normalized_result: #{normalized_result.inspect}" if CONFIG && CONFIG["EXTRA_LOGGING"]
        { success: false, error: "Generator returned empty content" }
      end
    rescue => e
      { success: false, error: "Generation failed: #{e.message}" }
    end

    def normalize_generation_result(result)
      return { mode: :full, content: result } if result.is_a?(String)
      return result if result.is_a?(Hash) && result[:mode]

      if result.is_a?(Hash) && result[:content]
        { mode: :full, content: result[:content] }
      else
        result
      end
    end

    def apply_patch_to_file(file_path, patch_text)

      Tempfile.create(['autoforge_patch', '.diff']) do |tmp|
        tmp.write(patch_text)
        tmp.flush

        strip_level = patch_text.include?('a/') || patch_text.include?('b/') ? 1 : 0

        apply_patch_safely(
          tmp.path,
          File.dirname(file_path),
          strip: strip_level
        )

        size = File.size(file_path)

        record_artifact(@project_id, File.basename(file_path), {
          size: size,
          generator: 'HtmlGenerator',
          mode: 'patch'
        })

        log_execution(@project_id, {
          action: 'patch_applied',
          file: File.basename(file_path),
          size: size
        })

        { success: true, file: File.basename(file_path) }
      end
    rescue => e
      { success: false, error: "Failed to apply patch: #{e.message}" }
    end

    def write_full_file(file_path, content)
      puts "[AutoForge] write_full_file called for: #{file_path}" if CONFIG && CONFIG["EXTRA_LOGGING"]
      puts "[AutoForge] Content to write length: #{content&.length || 0}" if CONFIG && CONFIG["EXTRA_LOGGING"]

      write_result = write_file_with_verification(file_path, content)
      puts "[AutoForge] write_file_with_verification result: #{write_result.inspect}" if CONFIG && CONFIG["EXTRA_LOGGING"]

      if write_result[:success]
        puts "[AutoForge] File write successful, recording artifacts" if CONFIG && CONFIG["EXTRA_LOGGING"]

        record_artifact(@project_id, File.basename(file_path), {
          size: write_result[:size],
          generator: 'HtmlGenerator',
          mode: 'full'
        })

        log_execution(@project_id, {
          action: 'file_written',
          file: File.basename(file_path),
          size: write_result[:size]
        })

        { success: true, file: File.basename(file_path) }
      else
        puts "[AutoForge] File write failed: #{write_result[:error]}" if CONFIG && CONFIG["EXTRA_LOGGING"]
        { success: false, error: "Failed to write file: #{write_result[:error]}" }
      end
    end
  end

  # Public interface for MDSL
  class App
    def initialize(context = {})
      @context = context || {}
      @orchestrator = Orchestrator.new(@context)
    end

    # Main method called from MDSL
    def generate_application(spec)
      # Normalize spec keys to symbols
      if spec.is_a?(Hash)
        spec = spec.transform_keys(&:to_sym) if spec.respond_to?(:transform_keys)
      end

      # Validate spec
      validation = AutoForgeUtils.validate_spec(spec)
      unless validation[:valid]
        return {
          success: false,
          error: "Invalid specification",
          details: validation[:errors]
        }
      end

      # Delegate to orchestrator
      @orchestrator.forge_project(spec)
    end

    # Convenience method for simple apps
    def create_simple_app(type, description, features = [])
      spec = {
        type: type,
        name: type.gsub(/[-_]/, ' ').split.map(&:capitalize).join(''),
        description: description,
        features: features
      }

      generate_application(spec)
    end
  end
end
