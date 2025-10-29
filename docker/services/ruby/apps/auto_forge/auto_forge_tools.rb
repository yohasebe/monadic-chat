# frozen_string_literal: true

require 'fileutils'
require 'securerandom'
require 'set'
require 'json'

require_relative 'auto_forge'
require_relative 'auto_forge_utils'
require_relative 'auto_forge_debugger'
require_relative 'agents/error_explainer'
require_relative 'utils/codex_response_analyzer'
require_relative '../../lib/monadic/agents/gpt5_codex_agent'
require_relative '../../lib/monadic/agents/claude_opus_agent'
require_relative '../../lib/monadic/agents/grok_code_agent'

# Tool methods for AutoForge MDSL application
# Uses GPT-5 for orchestration and GPT-5-Codex for code generation
module AutoForgeTools
  include MonadicHelper

  DIAGNOSIS_TIMEOUT = 30 * 60

  # The MDSL framework will automatically include the appropriate vendor helper
  # (OpenAIHelper, ClaudeHelper, etc) based on the provider configured in MDSL
  def generate_application(params = {})
    # Validate params structure
    if params.nil? || params.empty?
      return <<~RESPONSE
        ❌ Missing required parameters

        The generate_application tool requires a spec object with:
        - name: Application name (string)
        - type: Application type (string)
        - description: Clear description (string)
        - features: Array of features (array)

        Example:
        {
          "spec": {
            "name": "TodoApp",
            "type": "todo-list",
            "description": "A simple todo list application",
            "features": ["Add tasks", "Mark complete", "Delete tasks"]
          }
        }
      RESPONSE
    end

    # Handle both nested and direct spec formats
    spec = params['spec'] || params[:spec]
    agent = params['agent'] || params[:agent] || :openai
    agent = agent.to_sym rescue :openai

    # If no spec key, check if params itself is the spec
    if spec.nil? && params.is_a?(Hash)
      # Check if params looks like a spec (has name/type/description/features)
      if params['name'] || params[:name] || params['type'] || params[:type]
        spec = params
      end
    end

    # Still no spec found
    if spec.nil? || spec.empty?
      return <<~RESPONSE
        ❌ Invalid parameter structure

        Received: #{params.inspect}

        Expected structure:
        {
          "spec": {
            "name": "...",
            "type": "...",
            "description": "...",
            "features": [...]
          }
        }
      RESPONSE
    end

    # Detect project type from spec
    project_type = detect_project_type(spec)

    # Set both string and symbol keys to ensure compatibility
    spec['project_type'] = project_type
    spec[:project_type] = project_type

    # Create app instance with context
    # Note: Using local variable only to avoid race conditions with shared @context
    # Ensure context includes API key from environment if not already present
    context = {}
    if ENV['OPENAI_API_KEY'] && !context[:openai_api_key] && !context[:api_key]
      context = context.merge(openai_api_key: ENV['OPENAI_API_KEY'])
    end

    # Get session ID for progress broadcasting (multiple fallbacks)
    session_id = nil

    # Priority 1: Thread local WebSocket session ID
    if Thread.current[:websocket_session_id]
      session_id = Thread.current[:websocket_session_id]
      if CONFIG && CONFIG["EXTRA_LOGGING"]
        puts "[AutoForgeTools] Using WebSocket session ID from Thread.current: #{session_id}"
      end
    end

    # Priority 2: Rack session
    if session_id.nil? && Thread.current[:rack_session]
      rack_session = Thread.current[:rack_session]
      session_id = rack_session[:websocket_session_id] if rack_session.is_a?(Hash)
      if session_id && CONFIG && CONFIG["EXTRA_LOGGING"]
        puts "[AutoForgeTools] Using session ID from Rack session: #{session_id}"
      end
    end

    # Priority 3: Instance variable @session (legacy)
    if session_id.nil? && defined?(@session) && @session.is_a?(Hash)
      session_id = @session[:websocket_session_id] || @session[:session_id]
      if session_id && CONFIG && CONFIG["EXTRA_LOGGING"]
        puts "[AutoForgeTools] Using session ID from instance variable: #{session_id}"
      end
    end

    if session_id.nil? && CONFIG && CONFIG["EXTRA_LOGGING"]
      puts "[AutoForgeTools] Warning: No session ID available for progress updates"
    end

    # Debug logging to understand what self is
    puts "[AutoForgeTools] self class: #{self.class}" if CONFIG && CONFIG["EXTRA_LOGGING"]
    puts "[AutoForgeTools] self responds to call_gpt5_codex: #{self.respond_to?(:call_gpt5_codex)}" if CONFIG && CONFIG["EXTRA_LOGGING"]
    puts "[AutoForgeTools] self responds to api_request: #{self.respond_to?(:api_request)}" if CONFIG && CONFIG["EXTRA_LOGGING"]
    puts "[AutoForgeTools] self methods include call_gpt5_codex: #{self.methods.include?(:call_gpt5_codex)}" if CONFIG && CONFIG["EXTRA_LOGGING"]

    # If self has the method, it should work
    if self.respond_to?(:call_gpt5_codex)
      puts "[AutoForgeTools] ✓ self has call_gpt5_codex method" if CONFIG && CONFIG["EXTRA_LOGGING"]
    else
      puts "[AutoForgeTools] ✗ self does NOT have call_gpt5_codex method" if CONFIG && CONFIG["EXTRA_LOGGING"]
      # Check what modules are included
      puts "[AutoForgeTools] Included modules: #{self.class.included_modules.map(&:name).join(', ')}" if CONFIG && CONFIG["EXTRA_LOGGING"]
    end

    # Add self as app_instance so generators can access codegen methods
    context[:app_instance] = self
    context[:agent] = agent

    # Create progress callback for WebSocket broadcasting
    progress_callback = lambda do |fragment|
      # Try to send via WebSocketHelper with session ID
      if defined?(::WebSocketHelper)
        helper_class = ::WebSocketHelper

        if helper_class.respond_to?(:send_progress_fragment)
          begin
            # Send with session ID for targeted delivery
            helper_class.send_progress_fragment(fragment, session_id)

            if CONFIG && CONFIG["EXTRA_LOGGING"]
              puts "[AutoForgeTools] Sent progress to session #{session_id}: #{fragment["content"][0..50]}..." if fragment["content"]
            end
          rescue => e
            if CONFIG && CONFIG["EXTRA_LOGGING"]
              puts "[AutoForgeTools] Error sending progress: #{e.message}"
            end
          end
        end
      elsif CONFIG && CONFIG["EXTRA_LOGGING"]
        # Fallback to console output when WebSocketHelper not available
        puts "[AutoForgeTools] Progress (no WebSocket): #{fragment["content"]}" if fragment["content"]
      end
    end

    # Configure code generation callback based on agent
    # Dynamically extend the appropriate agent module to avoid helper conflicts
    context[:codex_callback] = case agent
    when :claude
      # Extend ClaudeOpusAgent to get claude_opus_agent method
      self.extend(Monadic::Agents::ClaudeOpusAgent) unless self.respond_to?(:claude_opus_agent)
      ->(prompt, app_name, &block) do
        actual_block = block || progress_callback
        self.claude_opus_agent(prompt, app_name || 'ClaudeOpusAgent', &actual_block)
      end
    when :grok
      # Extend GrokCodeAgent to get call_grok_code method
      self.extend(Monadic::Agents::GrokCodeAgent) unless self.respond_to?(:call_grok_code)
      ->(prompt, app_name, &block) do
        actual_block = block || progress_callback
        self.call_grok_code(prompt: prompt, app_name: app_name || 'AutoForgeGrok', &actual_block)
      end
    else
      # Extend GPT5CodexAgent to get call_gpt5_codex method
      self.extend(Monadic::Agents::GPT5CodexAgent) unless self.respond_to?(:call_gpt5_codex)
      ->(prompt, app_name, &block) do
        actual_block = block || progress_callback
        self.call_gpt5_codex(prompt: prompt, app_name: app_name || 'AutoForgeOpenAI', &actual_block)
      end
    end

    app = AutoForge::App.new(context)

    # Generate application with progress callback
    agent_name = case agent
                 when :claude then 'Claude Opus'
                 when :grok then 'Grok-Code-Fast-1'
                 else 'GPT-5-Codex'
                 end
    puts "\n⏳ Generating application with #{agent_name}... This may take 2-5 minutes for complex apps.\n"

    # Pass the progress callback to generate_application
    result = app.generate_application(spec, &progress_callback)

    # Store project info in context for additional file generation
    # Note: Only using local variable context to avoid race conditions with shared @context
    if result[:success]
      auto_forge = context[:auto_forge] || {}
      auto_forge[:project_path] = result[:project_path]
      auto_forge[:project_type] = project_type
      auto_forge[:project_id] = result[:project_id]
      auto_forge[:main_file] = result[:files_created]&.first if project_type == 'cli'
      context[:auto_forge] = auto_forge
      context['auto_forge'] = auto_forge if context.respond_to?(:[])
      # Removed @context assignment to prevent cross-session contamination
    end

    # Format response
    if result[:success]
      if project_type == 'cli'
          main_file = result[:files_created]&.first || 'script'
        suggestions = suggest_cli_additional_files(result[:project_path], main_file)
        suggestion_section = if suggestions.any?
          <<~TEXT

            I can also create these optional files if helpful:
            #{format_cli_suggestions(suggestions)}

            Just let me know if you need any of them.
          TEXT
        else
          ""
        end

        response_body = <<~TEXT
          ✅ CLI tool successfully generated!

          📁 Location: #{result[:project_path]}
          📄 Main script: #{main_file}

          To use:
          1. Navigate to: cd #{result[:project_path]}
          2. Make executable: chmod +x #{main_file}
          3. Run: ./#{main_file} --help
        TEXT

        response_body << suggestion_section unless suggestion_section.empty?

        response_body.rstrip
      else
        <<~RESPONSE
          ✅ Web application generated successfully!

          📁 Project Path: #{result[:project_path]}
          📄 Files Created: #{result[:files_created]&.join(', ') || 'index.html'}

          To view your application, open:
          #{File.join(result[:project_path], 'index.html')}
        RESPONSE
      end
    else
      # Strip any HTML tags from error messages to prevent rendering issues
      safe_error = (result[:error] || "Unknown error").to_s.gsub(/<[^>]*>/, '').strip[0..500]
      safe_message = result[:message] ? result[:message].to_s.gsub(/<[^>]*>/, '').strip[0..200] : nil
      safe_details = result[:details] ? result[:details].map { |d| d.to_s.gsub(/<[^>]*>/, '') } : nil

      <<~RESPONSE
        ❌ Generation failed

        Error: #{safe_error}
        #{safe_message ? "Details: #{safe_message}" : ''}
        #{safe_details ? "Validation: #{safe_details.join(', ')}" : ''}
      RESPONSE
    end
  rescue => e
    "❌ Error: #{e.message.gsub(/<.*?>/, '')[0..200]}\n\nPlease check server logs for details."
  end

  def validate_specification(params = {})
    # Validate params structure
    if params.nil? || params.empty?
      return <<~RESPONSE
        ❌ Missing required parameters

        The validate_specification tool requires a spec object with:
        - name: Application name (string)
        - type: Application type (string)
        - description: Clear description (string)
        - features: Array of features (array)

        Example:
        {
          "spec": {
            "name": "TodoApp",
            "type": "todo-list",
            "description": "A simple todo list application",
            "features": ["Add tasks", "Mark complete", "Delete tasks"]
          }
        }
      RESPONSE
    end

    # Handle both nested and direct spec formats
    spec = params['spec'] || params[:spec]

    # If no spec key, check if params itself is the spec
    if spec.nil? && params.is_a?(Hash)
      # Check if params looks like a spec
      if params['name'] || params[:name] || params['type'] || params[:type]
        spec = params
      end
    end

    # Still no spec found
    if spec.nil? || spec.empty?
      return <<~RESPONSE
        ❌ Invalid parameter structure

        Received: #{params.inspect}

        Please provide a complete specification.
      RESPONSE
    end

    validation = AutoForgeUtils.validate_spec(spec)

    if validation[:valid]
      <<~RESPONSE
        ✅ Specification is valid

        Ready to generate application with:
        - Name: #{spec[:name] || spec['name']}
        - Type: #{spec[:type] || spec['type']}
        - Description: #{spec[:description] || spec['description']}
        - Features: #{(spec[:features] || spec['features'] || []).join(', ')}
      RESPONSE
    else
      <<~RESPONSE
        ❌ Invalid specification

        Missing or invalid fields:
        #{validation[:errors].map { |e| "  - #{e}" }.join("\n")}

        All fields are required:
        - name: Application name
        - type: Application type
        - description: Clear description
        - features: Array of specific features
      RESPONSE
    end
  end

  def list_projects(params = {})
    projects = AutoForgeUtils.list_projects

    if projects.empty?
      "No AutoForge projects found"
    else
      lines = ["📁 AutoForge Projects:\n"]
      projects.each do |project|
        status = project[:has_index] ? "✅" : "🚧"
        lines << "  #{status} #{project[:base_name]} (#{project[:name]})"
        lines << "    Created: #{project[:created_at]}"
        lines << "    Path: #{project[:path]}"
        lines << ""
      end
      lines << "\n💡 To modify an existing app: Use the same name in generate_application"
      lines << "💡 To create a new version: Add \"reset\": true to the spec"
      lines.join("\n")
    end
  end

  def cleanup_old_projects(params = {})
    days = params['days'] || params[:days] || 7
    removed = AutoForgeUtils.cleanup_old_projects(days.to_i)

    if removed.empty?
      "No old projects to clean up"
    else
      "🗑️ Removed #{removed.size} old project(s):\n#{removed.map { |p| "  - #{p}" }.join("\n")}"
    end
  end

  def generate_additional_file(params = {})
    file_type = params['file_type'] || params[:file_type]
    file_name = params['file_name'] || params[:file_name]
    instructions = params['instructions'] || params[:instructions]

    # Handle both symbol and string keys for context
    context = @context || {}
    auto_forge = context[:auto_forge] || context['auto_forge'] || {}

    # Try both key formats for retrieval
    project_path = auto_forge[:project_path] || auto_forge['project_path']
    project_type = auto_forge[:project_type] || auto_forge['project_type'] ||
                   auto_forge[:current_project_type] || auto_forge['current_project_type']

    unless project_path && File.exist?(project_path)
      return "❌ No active project found. Please generate the main application first."
    end

    unless project_type == 'cli'
      return "ℹ️ Additional files are only available for CLI projects."
    end

    # Allow fully custom file generation when file_name and instructions are present
    if file_name && instructions
      result = generate_custom_cli_file(project_path, file_name, instructions)
      return result[:success] ? "✅ Created #{result[:filename]}" : "❌ Failed: #{result[:error]}"
    end

    unless file_type
      return <<~MSG.rstrip
        ❌ Missing required parameter: file_type

        You can also provide both "file_name" and "instructions" to generate any custom text-based file.
      MSG
    end

    result = generate_cli_additional_file(
      project_path,
      file_type,
      file_name: file_name,
      instructions: instructions
    )

    if result[:success]
      "✅ Created #{result[:filename]}"
    else
      "❌ Failed: #{result[:error]}"
    end
  end

  def debug_application(params = {})
    context = resolve_project_context(params)

    unless context[:success]
      return format_debug_context_error(context)
    end

    debugger = AutoForge::Debugger.new(@context)

    # Check Selenium availability with retries
    if error = debugger.send(:check_selenium_or_error)
      html_path = context[:html_path]
      return <<~RESPONSE
        ⚠️  #{error[:error]}

        #{error[:suggestion]}

        Note: The application can still be opened directly in your browser:
        #{html_path}
      RESPONSE
    end

    result = debugger.debug_html(context[:html_path])

    return format_debug_failure(result) unless result[:success]

    result[:project_name] = context[:project_name]
    result[:html_path] = context[:html_path]
    format_debug_report(result)
  rescue => e
    "❌ Debug error: #{e.message.gsub(/<.*?>/, '')[0..200]}"
  end

  def debug_application_raw(params = {})
    context = resolve_project_context(params)

    unless context[:success]
      return raw_error_hash(context)
    end

    debugger = AutoForge::Debugger.new(@context)

    # Check Selenium availability with retries
    if error = debugger.send(:check_selenium_or_error)
      return error.merge({
        project_name: context[:project_name],
        html_path: context[:html_path]
      })
    end

    result = debugger.debug_html(context[:html_path])
    result[:project_name] = context[:project_name]
    result[:html_path] = context[:html_path]
    result
  rescue => e
    { success: false, error: e.message, project_name: context[:project_name], html_path: context[:html_path] }
  end

  def diagnose_and_suggest_fixes(params = {})
    debug_result = debug_application_raw(params)

    unless debug_result[:success]
      return format_error_response(debug_result)
    end

    explainer = AutoForge::Agents::ErrorExplainer.new
    explanations = explainer.explain_errors(debug_result)

    diagnosis = {
      project_name: debug_result[:project_name],
      debug_result: debug_result,
      explanations: explanations,
      timestamp: Time.now,
      session_id: SecureRandom.hex(8)
    }

    store_diagnosis(diagnosis)
    format_diagnosis_response(diagnosis)
  end

  def apply_suggested_fixes(user_response = nil)
    diagnosis = current_diagnosis

    unless diagnosis
      return 'Please run diagnose_and_suggest_fixes first to identify issues.'
    end

    if diagnosis_expired?(diagnosis)
      clear_diagnosis_state
      return 'Diagnosis results have expired (30 minutes). Please run diagnosis again.'
    end

    handle_fix_response(user_response, diagnosis)
  end

  private

  def detect_project_type(spec)
    # Check both string and symbol keys
    description = (spec['description'] || spec[:description] || '').to_s.downcase
    name = (spec['name'] || spec[:name] || '').to_s.downcase
    type_hint = (spec['type'] || spec[:type] || '').to_s.downcase

    # CLI detection
    return 'cli' if type_hint.match?(/cli|command|tool|script|utility/)
    return 'web' if type_hint.match?(/web|html|app|dashboard/)

    # Keyword-based detection
    cli_keywords = %w[cli command script tool utility analyzer converter parser terminal]
    web_keywords = %w[web app dashboard interface ui page site browser]

    cli_score = cli_keywords.count { |w| description.include?(w) || name.include?(w) }
    web_score = web_keywords.count { |w| description.include?(w) || name.include?(w) }

    cli_score > web_score ? 'cli' : 'web'
  end

  def generate_cli_additional_file(project_path, file_type, options = {})
    key = file_type.to_s.downcase.to_sym

    case key
    when :readme
      create_readme(project_path)
    when :config
      create_config_template(project_path)
    when :requirements, :dependencies
      create_dependencies(project_path)
    when :usage_examples
      generate_usage_examples_file(project_path, options)
    else
      if options[:instructions] || options['instructions']
        inferred_name = options[:file_name] || options['file_name'] || default_filename_for_symbol(key)
        generate_custom_cli_file(project_path, inferred_name, options[:instructions] || options['instructions'])
      else
        {
          success: false,
          error: <<~ERROR.rstrip
            Unknown file type: #{file_type}

            Provide both "file_name" and "instructions" to generate a custom text file, for example:
            generate_additional_file({ "file_name": "USAGE.md", "instructions": "Document advanced usage scenarios with command examples." })
          ERROR
        }
      end
    end
  end

  def create_readme(project_path)
    # Validate project path
    validation_result = validate_file_path(project_path)
    if validation_result.is_a?(Hash)
      return { success: false, error: "Invalid project path: #{validation_result[:error]}" }
    end

    main_script, _content = read_cli_script(project_path)

    return { success: false, error: "No main script found" } unless main_script

    script_name = File.basename(main_script)
    project_name = File.basename(project_path).split('_').first

    readme = <<~README
      # #{project_name}

      Generated by AutoForge on #{Time.now.strftime('%Y-%m-%d')}

      ## Usage

      ```bash
      chmod +x #{script_name}
      ./#{script_name} --help
      ```

      ## Requirements

      See script header for details.
    README

    readme_path = File.join(project_path, 'README.md')
    readme_validation = validate_file_path(readme_path)
    if readme_validation.is_a?(Hash)
      return { success: false, error: "Invalid README path: #{readme_validation[:error]}" }
    end

    File.write(readme_path, readme)
    { success: true, filename: 'README.md' }
  end

  def create_config_template(project_path)
    # Validate project path
    validation_result = validate_file_path(project_path)
    if validation_result.is_a?(Hash)
      return { success: false, error: "Invalid project path: #{validation_result[:error]}" }
    end

    main_script, content = read_cli_script(project_path)

    return { success: false, error: "No main script found" } unless main_script && content

    preview = content[0, 500]
    ext = File.extname(main_script)

    case ext
    when '.py'
      config = "# Configuration file\n[settings]\ndebug = false\nverbose = false\n"
      filename = 'config.ini'
    when '.rb'
      config = "# Configuration file\ndebug: false\nverbose: false\n"
      filename = 'config.yml'
    when '.js'
      config = "{\n  \"debug\": false,\n  \"verbose\": false\n}\n"
      filename = 'config.json'
    else
      config = "# Configuration file\nDEBUG=false\nVERBOSE=false\n"
      filename = 'config.cfg'
    end

    config_path = File.join(project_path, filename)
    config_validation = validate_file_path(config_path)
    if config_validation.is_a?(Hash)
      return { success: false, error: "Invalid config path: #{config_validation[:error]}" }
    end

    File.write(config_path, config)
    { success: true, filename: filename }
  end

  def create_dependencies(project_path)
    # Validate project path
    validation_result = validate_file_path(project_path)
    if validation_result.is_a?(Hash)
      return { success: false, error: "Invalid project path: #{validation_result[:error]}" }
    end

    main_script, content = read_cli_script(project_path)

    return { success: false, error: "No main script found" } unless main_script && content

    ext = File.extname(main_script)
    dependencies = detect_external_dependencies(content, ext)

    case ext
    when '.py'
      filename = 'requirements.txt'
      body = dependencies.any? ? dependencies.sort.join("\n") : "# No external dependencies detected\n"
    when '.rb'
      filename = 'Gemfile'
      body = if dependencies.any?
        gems = dependencies.sort.map { |d| "gem '#{d}'" }.join("\n")
        "source 'https://rubygems.org'\n\n#{gems}\n"
      else
        "# No external dependencies detected\n"
      end
    when '.js'
      filename = 'package.json'
      body = if dependencies.any?
        deps_json = dependencies.sort.map { |d| "    \"#{d}\": \"latest\"" }.join(",\n")
        "{\n  \"name\": \"autoforge-cli\",\n  \"version\": \"1.0.0\",\n  \"dependencies\": {\n#{deps_json}\n  }\n}\n"
      else
        "{\n  \"name\": \"autoforge-cli\",\n  \"version\": \"1.0.0\",\n  \"dependencies\": {}\n}\n"
      end
    else
      filename = 'dependencies.txt'
      body = "# No external dependencies detected\n"
    end

    # Validate the target file path
    file_path = File.join(project_path, filename)
    file_validation = validate_file_path(file_path)
    if file_validation.is_a?(Hash)
      return { success: false, error: "Invalid file path: #{file_validation[:error]}" }
    end

    File.write(file_path, body)
    { success: true, filename: filename }
  end

  # Load standard library lists from external configuration
  def load_standard_libraries
    config_file = File.join(File.dirname(__FILE__), 'config', 'standard_libraries.json')
    if File.exist?(config_file)
      begin
        config = JSON.parse(File.read(config_file))
        {
          python: Set.new(config['python'] || []),
          ruby: Set.new(config['ruby'] || []),
          node: Set.new(config['node'] || [])
        }
      rescue JSON::ParserError => e
        puts "[AutoForge] Error loading standard libraries config: #{e.message}" if CONFIG && CONFIG["EXTRA_LOGGING"]
        default_standard_libraries
      end
    else
      puts "[AutoForge] Standard libraries config not found, using defaults" if CONFIG && CONFIG["EXTRA_LOGGING"]
      default_standard_libraries
    end
  end

  def default_standard_libraries
    {
      python: Set.new(%w[
        argparse array base64 calendar collections concurrent decimal errno fcntl
        functools glob hashlib heapq http io itertools json logging math os pathlib
        random re sched shutil signal socket statistics string struct subprocess sys
        tempfile textwrap threading time typing uuid xml zipfile datetime zoneinfo
        gzip csv ssl sqlite3 unicodedata platform getpass inspect pprint
      ]),
      ruby: Set.new(%w[
        abbrev base64 benchmark bigdecimal cgi csv date dbm digest drb etc fcntl
        fileutils find forwardable getoptlong ipaddr logger mathn monitor mutex_m
        net/ftp net/http net/imap net/pop net/smtp open-uri optparse ostruct pathname
        pp pstore resolv securerandom set shell tempfile time yaml zlib json
      ]),
      node: Set.new(%w[
        assert buffer child_process crypto dns events fs http https net os path
        process readline stream string_decoder timers tty url util zlib
      ])
    }
  end

  # Lazy load standard libraries
  def standard_libraries
    @standard_libraries ||= load_standard_libraries
  end

  def suggest_cli_additional_files(project_path, main_file)
    suggestions = []

    readme_path = File.join(project_path, 'README.md')
    suggestions << build_cli_suggestion(:readme, label: 'README (usage instructions)') unless File.exist?(readme_path)

    script_path, content = read_cli_script(project_path)
    return append_custom_suggestion(suggestions) unless script_path && content

    ext = File.extname(script_path)
    normalized_content = content.to_s

    if cli_script_uses_config?(normalized_content)
      suggestions << build_cli_suggestion(:config, label: 'Config template (sample settings)')
    end

    if detect_external_dependencies(normalized_content, ext).any?
      suggestions << build_cli_suggestion(:dependencies, label: 'Dependencies file (e.g. requirements.txt)')
    end

    if cli_script_has_argument_parser?(normalized_content)
      suggestions << build_cli_suggestion(
        :usage_examples,
        label: 'Usage examples (USAGE.md)',
        file_name: 'USAGE.md',
        instructions_hint: 'Describe common commands, flags, and sample outputs.'
      )
    end

    append_custom_suggestion(suggestions)
  rescue StandardError => e
    puts "[AutoForge] Error in suggest_cli_additional_files: #{e.message}" if CONFIG && CONFIG["EXTRA_LOGGING"]
    append_custom_suggestion(suggestions)
  end

  def format_cli_suggestions(suggestions)
    Array(suggestions).map do |entry|
      if entry.is_a?(Hash)
        key = entry[:key] || :custom
        label = entry[:label] || key.to_s.split('_').map(&:capitalize).join(' ')
        hint = build_cli_suggestion_hint(entry)
        next nil unless hint
        "• #{label} — #{hint}"
      else
        case entry
        when :readme then "• README (usage instructions)"
        when :config then "• Config template (sample settings)"
        when :dependencies then "• Dependencies file (e.g. requirements.txt)"
        else
          "• Custom asset — provide \"file_name\" and \"instructions\" to generate any text-based file"
        end
      end
    end.compact.join("\n")
  end

  def read_cli_script(project_path)
    # Note: Removed @context fallback to prevent cross-session contamination
    # Project state is now tracked through the filesystem only

    # Try to find the main CLI script by looking for shebang
    fallback = Dir.glob(File.join(project_path, '*')).find do |f|
      File.file?(f) && !f.end_with?('.json', '.md', '.txt') && File.read(f, 100).include?('#!')
    end

    return [fallback, File.read(fallback)] if fallback

    [nil, nil]
  rescue StandardError => e
    puts "[AutoForge] Error in read_cli_script: #{e.message}" if CONFIG && CONFIG["EXTRA_LOGGING"]
    [nil, nil]
  end

  def cli_script_uses_config?(content)
    return false unless content

    !!(content =~ /configparser|ConfigParser|yaml|toml|dotenv|--config|config file/i)
  end

  def cli_script_has_argument_parser?(content)
    return false unless content

    !!(content =~ /argparse|ArgumentParser|optparse|OptionParser|click::|Typer|Thor::|OptionParser.new/i)
  end

  def detect_external_dependencies(content, extension)
    return [] unless content

    case extension
    when '.py'
      imports = content.scan(/^(?:import|from)\s+([a-zA-Z_][\w]*)/).flatten.map { |m| m.split('.').first.downcase }.uniq
      imports.reject { |mod| standard_libraries[:python].include?(mod) }
    when '.rb'
      requires = content.scan(/^require\s+['"]([^'"]+)['"]/).flatten.map { |mod| mod.downcase }.uniq
      requires.reject { |mod| mod.start_with?('.') || standard_libraries[:ruby].include?(mod) }
    when '.js'
      requires = content.scan(/require\(['"]([^'"]+)['"]\)/).flatten
      imports = content.scan(/import\s+.*?from\s+['"]([^'"]+)['"]/).flatten
      modules = (requires + imports).map { |mod| mod.downcase }.uniq
      modules.reject { |mod| mod.start_with?('.') || standard_libraries[:node].include?(mod) }
    else
      []
    end
  end

  def generate_usage_examples_file(project_path, options = {})
    file_name = options[:file_name] || options['file_name'] || 'USAGE.md'
    instructions = options[:instructions] || options['instructions'] || <<~DESC.strip
      Create a Markdown document that teaches users how to run the CLI tool. Include:
      - A short summary of what the tool does.
      - A table or list of important command-line flags and options.
      - At least three realistic usage scenarios with the exact commands and expected outputs.
      - Troubleshooting tips for common mistakes.
    DESC

    generate_custom_cli_file(project_path, file_name, instructions, usage_examples: true)
  end

  def generate_custom_cli_file(project_path, file_name, instructions, usage_examples: false)
    validation = validate_custom_file_request(file_name, instructions)
    return validation unless validation[:success]

    target_file = File.join(project_path, validation[:file_name])
    generator = resolve_text_generator

    unless generator
      return { success: false, error: 'No code generation agent available for additional file creation.' }
    end

    prompt = build_custom_file_prompt(project_path, validation[:file_name], validation[:instructions], usage_examples: usage_examples)

    result = generator.call(prompt, 'AutoForgeAdditionalFile')
    normalized = normalize_text_generation_result(result)

    return { success: false, error: normalized[:error] } unless normalized[:success]

    File.write(target_file, normalized[:content])

    { success: true, filename: validation[:file_name] }
  rescue StandardError => e
    {
      success: false,
      error: e.message
    }
  end

  def validate_custom_file_request(file_name, instructions)
    unless file_name && file_name.is_a?(String)
      return { success: false, error: 'Missing required parameter: file_name' }
    end

    sanitized = sanitize_filename(file_name)

    unless sanitized
      return { success: false, error: 'Invalid file name. Use simple names without directory separators.' }
    end

    trimmed_instructions = instructions.to_s.strip

    if trimmed_instructions.empty?
      return { success: false, error: 'Please provide "instructions" describing the purpose and desired content.' }
    end

    { success: true, file_name: sanitized, instructions: trimmed_instructions }
  end

  def sanitize_filename(name)
    candidate = name.to_s.strip
    return nil if candidate.empty?
    return nil if candidate.match?(%r{[\/\\]}) || candidate.include?(" ") || candidate.include?('..')

    sanitized = candidate.gsub(/[^a-z0-9._-]/i, '_')
    sanitized = sanitized[0, 128]
    return nil if sanitized.empty? || sanitized.start_with?('.')
    sanitized
  end

  def resolve_text_generator
    # Note: Removed @context usage to prevent cross-session contamination
    # Default to OpenAI agent

    if respond_to?(:call_gpt5_codex)
      ->(prompt, app_name = 'AutoForgeAdditionalFile', &block) { call_gpt5_codex(prompt: prompt, app_name: app_name, &block) }
    else
      nil
    end
  end

  def build_custom_file_prompt(project_path, file_name, instructions, usage_examples: false)
    script_path, script_content = read_cli_script(project_path)
    script_excerpt = truncate_text(script_content.to_s, 4000)

    existing_files = Dir.children(project_path).reject { |f| f.start_with?('.') }.sort.join(', ')
    project_name = File.basename(project_path)

    additional_guidance = if usage_examples
      <<~GUIDE
        Structure:
        - Introduction
        - Quick start section
        - Detailed scenarios (each with command, explanation, expected output)
        - Troubleshooting / tips
      GUIDE
    else
      ''
    end

    <<~PROMPT
      You are assisting with the AutoForge CLI project "#{project_name}".
      Create a new text file named "#{file_name}" in the project root.

      Main script excerpt:
      ```
      #{script_excerpt}
      ```

      Existing files: #{existing_files}

      Purpose:
      #{instructions}

      #{additional_guidance}

      Requirements:
      - Produce complete, ready-to-use content tailored to the script.
      - Use Markdown formatting if the filename ends with .md or .markdown.
      - Do not include placeholder text or instructions to "fill in later".
      - Output ONLY the file contents with no surrounding commentary or code fences.
    PROMPT
  end

  def normalize_text_generation_result(result)
    return { success: false, error: 'No response from generation agent' } if result.nil?

    if result.is_a?(Hash)
      return { success: false, error: fetch_from_hash(result, :error) || 'Unknown error' } if fetch_from_hash(result, :success) == false

      text = fetch_from_hash(result, :code) || fetch_from_hash(result, :content) || fetch_from_hash(result, :text)
      return { success: false, error: 'Empty response' } if text.nil? || text.strip.empty?
      cleaned = strip_code_fences(text)
      return { success: true, content: cleaned }
    end

    cleaned = strip_code_fences(result.to_s)
    cleaned.strip.empty? ? { success: false, error: 'Empty response' } : { success: true, content: cleaned }
  end

  def strip_code_fences(text)
    text.to_s.gsub(/```[a-zA-Z0-9_-]*\n?/, '').gsub(/```/, '').strip
  end

  def truncate_text(text, limit)
    return '' unless text

    text.length <= limit ? text : text[0, limit] + "\n…"
  end
  def handle_fix_response(user_response, diagnosis)
    response = (user_response || '').downcase

    case response
    when /fix|apply|yes|correct/
      apply_automatic_fixes(diagnosis)
    when /detail|technical|more/
      show_technical_details(diagnosis)
    when /skip|no|ignore|cancel/
      clear_diagnosis_state
      'Understood. No fixes will be applied.'
    else
      prompt_for_valid_response
    end
  end

  def apply_automatic_fixes(diagnosis)
    errors = fetch_array(diagnosis[:debug_result], :javascript_errors)
    return 'No errors to fix.' if errors.empty?

    unless respond_to?(:call_gpt5_codex)
      return 'Error correction requires GPT-5-Codex access.'
    end

    fix_prompt = build_fix_prompt(diagnosis[:explanations], errors)
    puts '[AutoForge] Calling GPT-5-Codex for fixes...' if CONFIG && CONFIG['EXTRA_LOGGING']

    codex_result = call_gpt5_codex(
      prompt: fix_prompt,
      app_name: 'AutoForgeErrorFixer'
    )

    if codex_result[:success]
      apply_codex_fix(diagnosis, codex_result[:code])
    else
      error_msg = fetch_from_hash(codex_result, :error) || 'Unknown error from GPT-5-Codex'
      "Failed to generate fixes: #{error_msg}\n\nYou may want to try again or fix manually."
    end
  end

  def apply_codex_fix(diagnosis, code_content)
    project_name = diagnosis[:project_name]
    project_info = AutoForgeUtils.find_recent_project(project_name)

    unless project_info
      clear_diagnosis_state
      return 'Project no longer exists.'
    end

    html_path = File.join(project_info[:path], 'index.html')
    existing_content = File.exist?(html_path) ? File.read(html_path) : nil

    mode, fix_content = AutoForge::Utils::CodexResponseAnalyzer.analyze_response(
      code_content,
      existing_content: existing_content
    )

    if mode == :unknown || fix_content.nil?
      return 'Could not understand the fix format. Please try again.'
    end

    result = apply_fix_with_backup(html_path, mode, fix_content, diagnosis)
    clear_diagnosis_state if result[:success]
    result[:message]
  end

  def apply_fix_with_backup(html_path, fix_mode, fix_content, diagnosis)
    backup_path = "#{html_path}.backup_#{Time.now.to_i}"
    project_name = diagnosis[:project_name]

    begin
      FileUtils.cp(html_path, backup_path)

      apply_result = case fix_mode
                     when :patch
                       apply_patch_to_file(html_path, fix_content)
                     when :full
                       write_full_file(html_path, fix_content)
                     else
                       { success: false, error: 'Invalid fix mode' }
                     end

      unless apply_result[:success]
        FileUtils.mv(backup_path, html_path, force: true)
        return {
          success: false,
          message: "Failed to apply fixes: #{apply_result[:error]}. Original file restored."
        }
      end

      verification = debug_application_raw('spec' => { 'name' => project_name })

      if !verification[:success] && (fetch_from_hash(verification, :error) || '').include?('Selenium')
        File.delete(backup_path) if File.exist?(backup_path)
        return {
          success: true,
          message: <<~MSG
            ⚠️ Fixes applied but could not verify

            The fixes have been applied successfully, but verification
            could not be completed because Selenium is not available.

            Location: #{html_path}

            To verify the fixes later, run diagnose_and_suggest_fixes
            when Selenium is available.
          MSG
        }
      elsif verification[:success]
        File.delete(backup_path) if File.exist?(backup_path)
        remaining_errors = fetch_array(verification, :javascript_errors).length

        if remaining_errors.zero?
          {
            success: true,
            message: <<~MSG
              ✅ Fixes applied and verified successfully!

              All issues have been resolved.
              #{project_name} is now working correctly.

              Location: #{html_path}
            MSG
          }
        else
          {
            success: true,
            message: <<~MSG
              ⚠️ Fixes applied with remaining issues

              #{remaining_errors} issue(s) still remain.

              You may want to run diagnosis again.
            MSG
          }
        end
      else
        FileUtils.mv(backup_path, html_path, force: true)
        {
          success: false,
          message: "Verification failed: #{fetch_from_hash(verification, :error)}. Original file restored."
        }
      end
    rescue => e
      FileUtils.mv(backup_path, html_path, force: true) if File.exist?(backup_path)
      {
        success: false,
        message: "Unexpected error during fix: #{e.message}. Original file restored."
      }
    end
  end

  def build_fix_prompt(explanations, errors)
    explanation_lines = explanations.map do |exp|
      title = fetch_from_hash(exp, :title)
      detail = fetch_from_hash(exp, :explanation)
      "- #{title}: #{detail}"
    end

    error_lines = errors.map do |error|
      message = fetch_from_hash(error, :message)
      "- #{message}"
    end

    <<~PROMPT
      Fix JavaScript errors in an HTML application.

      Issues found (user-friendly descriptions):
      #{explanation_lines.join("\n")}

      Technical errors:
      #{error_lines.join("\n")}

      Requirements:
      1. Fix all identified JavaScript errors
      2. Add proper error handling to prevent future issues
      3. Preserve all existing functionality
      4. Ensure cross-browser compatibility
      5. Add comments explaining the fixes

      Return EITHER:
      - A unified diff patch (for localized changes)
      - Complete fixed HTML file (for extensive changes)

      Do not include explanations outside of code comments.
    PROMPT
  end

  def show_technical_details(diagnosis)
    errors = fetch_array(diagnosis[:debug_result], :javascript_errors)
    warnings = fetch_array(diagnosis[:debug_result], :warnings)
    performance = fetch_from_hash(diagnosis[:debug_result], :performance) || {}
    load_time = format_ms(fetch_from_hash(performance, :loadTime))
    dom_ready = format_ms(fetch_from_hash(performance, :domReadyTime))
    render_time = format_ms(fetch_from_hash(performance, :renderTime))

    <<~RESPONSE
      📋 Technical Details

      ## JavaScript Errors (#{errors.length}):
      #{errors.map { |e| "```\n#{fetch_from_hash(e, :message)}\n```" }.join("\n")}

      ## Warnings (#{warnings.length}):
      #{warnings.map { |w| "```\n#{fetch_from_hash(w, :message)}\n```" }.join("\n")}

      ## Performance Metrics:
      - Load Time: #{load_time}
      - DOM Ready: #{dom_ready}
      - Render Time: #{render_time}

      To fix these issues automatically, type "apply fixes".
    RESPONSE
  end

  def prompt_for_valid_response
    <<~RESPONSE
      Please choose an option:
      • "apply fixes" - Automatically fix the issues
      • "show details" - See technical information
      • "skip" - Continue without fixing
    RESPONSE
  end

  def store_diagnosis(diagnosis)
    # Note: Using instance variable only. This means diagnosis state is scoped to
    # a single tool execution, which is acceptable since diagnoses expire quickly.
    @last_diagnosis = diagnosis
  end

  def current_diagnosis
    @last_diagnosis
  end

  def diagnosis_expired?(diagnosis)
    timestamp = fetch_from_hash(diagnosis, :timestamp)
    return true unless timestamp.is_a?(Time)

    (Time.now - timestamp) > DIAGNOSIS_TIMEOUT
  end

  def clear_diagnosis_state
    @last_diagnosis = nil
  end

  def resolve_project_context(params)
    spec = normalize_spec(params)
    manual_path = fetch_from_hash(spec, :project_path) || fetch_from_hash(spec, :project_dir)
    manual_path = manual_path.to_s.strip

    project_name = fetch_from_hash(spec, :name)&.to_s&.strip

    if manual_path && !manual_path.empty?
      expanded_path = File.expand_path(manual_path)

      # Validate the path is within the shared folder
      data_dir = Monadic::Utils::Environment.data_path
      validation_result = validate_file_path(expanded_path)
      if validation_result.is_a?(Hash)
        return {
          success: false,
          error_type: :invalid_path,
          project_name: project_name,
          error: "Invalid project path: #{validation_result[:error]}"
        }
      end

      unless Dir.exist?(expanded_path)
        return {
          success: false,
          error_type: :manual_path_missing,
          project_name: project_name,
          project_path: expanded_path,
          html_path: File.join(expanded_path, 'index.html')
        }
      end

      html_path = File.join(expanded_path, 'index.html')

      # Validate HTML path as well
      html_validation = validate_file_path(html_path)
      if html_validation.is_a?(Hash)
        return {
          success: false,
          error_type: :invalid_path,
          project_name: project_name,
          error: "Invalid HTML path: #{html_validation[:error]}"
        }
      end

      unless File.exist?(html_path)
        return {
          success: false,
          error_type: :missing_index,
          project_name: project_name || File.basename(expanded_path),
          project_path: expanded_path,
          html_path: html_path
        }
      end

      resolved_name = project_name && !project_name.empty? ? project_name : File.basename(expanded_path)

      return {
        success: true,
        spec: spec,
        project_name: resolved_name,
        project_info: { path: expanded_path, name: resolved_name },
        html_path: html_path
      }
    end

    return { success: false, error_type: :missing_name } if project_name.nil? || project_name.empty?

    project_info = AutoForgeUtils.find_recent_project(project_name)
    unless project_info
      return {
        success: false,
        error_type: :project_not_found,
        project_name: project_name
      }
    end

    html_path = File.join(project_info[:path], 'index.html')

    unless File.exist?(html_path)
      return {
        success: false,
        error_type: :missing_index,
        project_name: project_name,
        project_path: project_info[:path],
        html_path: html_path
      }
    end

    {
      success: true,
      spec: spec,
      project_name: project_name,
      project_info: project_info,
      html_path: html_path
    }
  end

  def format_debug_context_error(context)
    case context[:error_type]
    when :missing_name
      <<~RESPONSE
        ❌ Missing project name

        Please specify which project to debug:
        {
          "spec": {
            "name": "ProjectName"
          }
        }
      RESPONSE
    when :project_not_found
      project_name = context[:project_name]
      <<~RESPONSE
        ❌ Project not found: #{project_name}

        Use list_projects to see available projects.
      RESPONSE
    when :missing_index
      project_name = context[:project_name]
      project_path = context[:project_path]
      <<~RESPONSE
        ❌ No index.html found in project: #{project_name}

        Project path: #{project_path}
      RESPONSE
    when :manual_path_missing
      project_path = context[:project_path]
      <<~RESPONSE
        ❌ Project directory not found

        Expected path: #{project_path}
        Ensure the directory exists and contains an index.html file.
      RESPONSE
    else
      message = context[:error] || 'Unknown error'
      "❌ Debug failed\n\n#{message}"
    end
  end

  def raw_error_hash(context)
    message = case context[:error_type]
              when :missing_name
                'Missing project name'
              when :project_not_found
                "Project not found: #{context[:project_name]}"
              when :missing_index
                "No index.html found in project: #{context[:project_name]}"
              when :manual_path_missing
                "Project directory not found: #{context[:project_path]}"
              else
                context[:error] || 'Unknown error'
              end

    {
      success: false,
      error: message,
      project_name: context[:project_name],
      project_path: context[:project_path],
      html_path: context[:html_path]
    }
  end

  def format_debug_failure(result)
    error_message = fetch_from_hash(result, :error) || 'Unknown error'
    <<~RESPONSE
      ❌ Debug failed

      Error: #{error_message}

      Please check that:
      1. The Selenium container is running properly
      2. The HTML file exists and is readable
      3. There are no Docker networking issues
    RESPONSE
  end

  def format_debug_report(result)
    project_name = result[:project_name]
    report = String.new
    report << "🔍 Debug Report for #{project_name}\n"
    report << "=====================================\n\n"

    summary = fetch_array(result, :summary)
    report << summary.join("\n") << "\n\n" unless summary.empty?

    errors = fetch_array(result, :javascript_errors)
    unless errors.empty?
      report << "\n❌ JavaScript Errors:\n"
      errors.each { |error| report << "  • #{fetch_from_hash(error, :message)}\n" }
    end

    warnings = fetch_array(result, :warnings)
    unless warnings.empty?
      report << "\n⚠️  Warnings:\n"
      warnings.each { |warning| report << "  • #{fetch_from_hash(warning, :message)}\n" }
    end

    tests = fetch_array(result, :tests)
    unless tests.empty?
      report << "\n🧪 Functionality Tests:\n"
      tests.each do |test|
        status = fetch_from_hash(test, :passed) ? '✅' : '❌'
        count = fetch_from_hash(test, :count)
        label = fetch_from_hash(test, :test)
        report << "  #{status} #{label}"
        report << " (#{count})" if count
        report << "\n"
      end
    end

    performance = fetch_from_hash(result, :performance) || {}
    unless performance.empty?
      report << "\n⚡ Performance Metrics:\n"
      load_time = fetch_from_hash(performance, :loadTime)
      dom_ready = fetch_from_hash(performance, :domReadyTime)
      render_time = fetch_from_hash(performance, :renderTime)
      report << "  • Load Time: #{load_time}ms\n" if load_time
      report << "  • DOM Ready: #{dom_ready}ms\n" if dom_ready
      report << "  • Render Time: #{render_time}ms\n" if render_time
    end

    debug_timing = fetch_from_hash(result, :debug_timing) || {}
    unless debug_timing.empty?
      report << "\n⏱️  Debug Timing:\n"
      duration = fetch_from_hash(debug_timing, :duration)
      report << "  • Total Duration: #{duration} seconds\n" if duration

      selenium_timing = fetch_from_hash(result, :selenium_timing) || {}
      connect_time = fetch_from_hash(selenium_timing, :connect_time)
      page_load_time = fetch_from_hash(selenium_timing, :page_load_time)
      report << "  • Selenium Connect: #{connect_time}s\n" if connect_time
      report << "  • Page Load: #{page_load_time}s\n" if page_load_time
    end

    html_path = result[:html_path]
    report << "\n📁 File Location: #{html_path}"
    report
  end

  def format_error_response(result)
    message = fetch_from_hash(result, :error) || 'Unknown error'
    hint = fetch_from_hash(result, :hint)

    parts = ["❌ Diagnosis failed", '', message]
    parts << "Hint: #{hint}" if hint
    parts.join("\n")
  end

  def format_diagnosis_response(diagnosis)
    project_name = diagnosis[:project_name]
    explanations = fetch_array(diagnosis, :explanations)

    if explanations.empty?
      performance = fetch_from_hash(fetch_from_hash(diagnosis, :debug_result), :performance) || {}
      load_time = format_ms(fetch_from_hash(performance, :loadTime))
      render_time = format_ms(fetch_from_hash(performance, :renderTime))

      return <<~RESPONSE
        ✅ Diagnosis Complete: No issues found!

        #{project_name} is working correctly.

        Performance metrics:
        - Load time: #{load_time}
        - Render time: #{render_time}

        Interactive elements:
        - Forms: #{count_elements(diagnosis[:debug_result], 'form')}
        - Buttons: #{count_elements(diagnosis[:debug_result], 'button')}
      RESPONSE
    end

    severity_counts = Hash.new(0)
    explanations.each do |exp|
      severity = fetch_from_hash(exp, :severity)
      severity_counts[severity.to_s.to_sym] += 1
    end

    header = <<~HEADER
      🔍 Diagnosis Results for #{project_name}

      Found #{explanations.length} issue(s):
      #{severity_counts.map { |sev, count| "• #{severity_icon(sev)} #{count} #{sev}" }.join("\n")}

      ## Issues:

    HEADER

    body = explanations.each_with_index.map do |exp, index|
      title = fetch_from_hash(exp, :title)
      explanation = fetch_from_hash(exp, :explanation)
      impact = fetch_from_hash(exp, :impact)
      severity = fetch_from_hash(exp, :severity)

      <<~ISSUE
        ### #{index + 1}. #{severity_icon(severity)} #{title}

        **What's wrong:** #{explanation}
        **Impact:** #{impact}

      ISSUE
    end.join

    header + body + <<~OPTIONS

      ## What would you like to do?

      1️⃣ **Apply fixes** (recommended)
         Type: "apply fixes"

      2️⃣ **See technical details**
         Type: "show details"

      3️⃣ **Skip for now**
         Type: "skip"
    OPTIONS
  end

  def severity_icon(severity)
    case severity.to_s
    when 'critical' then '🔴'
    when 'high' then '🟠'
    when 'medium' then '🟡'
    when 'low' then '🟢'
    else '⚪'
    end
  end

  def count_elements(debug_result, element_type)
    tests = fetch_array(debug_result, :functionality_tests)
    test = tests.find { |t| (fetch_from_hash(t, :test) || '').include?(element_type) }
    fetch_from_hash(test, :count) || 0
  end

  def normalize_spec(params)
    return {} unless params.is_a?(Hash)
    params['spec'] || params[:spec] || params
  end

  def fetch_from_hash(record, key)
    return nil unless record.is_a?(Hash)
    record[key] || record[key.to_s]
  end

  def fetch_array(record, key)
    Array(fetch_from_hash(record, key))
  end


  def append_custom_suggestion(existing)
    return existing if existing.any? { |entry| entry.is_a?(Hash) && entry[:key] == :custom }

    hint = 'Provide "file_name" and "instructions" to generate any additional text asset (e.g. USAGE.md, CHANGELOG.md, SAMPLE_DATA.txt).'
    existing << build_cli_suggestion(:custom, label: 'Custom asset', instructions_hint: hint)
    existing
  end

  def build_cli_suggestion(key, attributes = {})
    { key: key }.merge(attributes)
  end

  def build_cli_suggestion_hint(entry)
    key = entry[:key]

    case key
    when :readme, :config, :dependencies
      "use `generate_additional_file({ \"file_type\": \"#{key}\" })`"
    when :usage_examples
      "use `generate_additional_file({ \"file_type\": \"usage_examples\" })` (optional: override with `file_name` or `instructions`)"
    when :custom
      entry[:instructions_hint] || "provide \"file_name\" and \"instructions\" to the tool request"
    else
      "provide \"file_name\" and \"instructions\" to generate this file"
    end
  end

  def default_filename_for_symbol(key)
    case key
    when :usage_examples then 'USAGE.md'
    when :changelog then 'CHANGELOG.md'
    when :env then '.env.example'
    else
      "#{key.to_s.gsub(/[^a-z0-9]+/i, '_')}.txt"
    end
  end

  def format_ms(value)
    value ? "#{value}ms" : 'n/a'
  end
end
