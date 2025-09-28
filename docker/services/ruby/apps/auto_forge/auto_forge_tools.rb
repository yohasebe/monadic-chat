# frozen_string_literal: true

require 'fileutils'
require 'securerandom'

require_relative 'auto_forge'
require_relative 'auto_forge_utils'
require_relative 'auto_forge_debugger'
require_relative 'agents/error_explainer'
require_relative 'utils/codex_response_analyzer'
require_relative '../../lib/monadic/agents/gpt5_codex_agent'

# Tool methods for AutoForge MDSL application
# Uses GPT-5 for orchestration and GPT-5-Codex for code generation
module AutoForgeTools
  include MonadicHelper
  include Monadic::Agents::GPT5CodexAgent

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

    # Create app instance with context
    # Ensure context includes API key from environment if not already present
    context = @context || {}
    if ENV['OPENAI_API_KEY'] && !context[:openai_api_key] && !context[:api_key]
      context = context.merge(openai_api_key: ENV['OPENAI_API_KEY'])
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

    # Add self as app_instance so HtmlGenerator can access GPT-5-Codex methods
    context[:app_instance] = self

    # Also add a callback as fallback
    if self.respond_to?(:call_gpt5_codex)
      context[:codex_callback] = ->(prompt, app_name) do
        self.call_gpt5_codex(prompt: prompt, app_name: app_name)
      end
    end

    app = AutoForge::App.new(context)

    # Generate application
    puts "\n⏳ Generating application with GPT-5-Codex... This may take 2-5 minutes for complex apps.\n"
    result = app.generate_application(spec)

    # Format response
    if result[:success]
      <<~RESPONSE
        ✅ Application generated successfully!

        📁 Project Path: #{result[:project_path]}
        📄 Files Created: #{result[:files_created]&.join(', ') || 'index.html'}

        To view your application, open:
        #{File.join(result[:project_path], 'index.html')}
      RESPONSE
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

  def debug_application(params = {})
    context = resolve_project_context(params)

    unless context[:success]
      return format_debug_context_error(context)
    end

    debugger = AutoForge::Debugger.new(@context)

    unless debugger.send(:selenium_available?)
      html_path = context[:html_path]
      return <<~RESPONSE
        ⚠️  Selenium container is not running

        The debug feature requires the Selenium container to be active.
        To enable debugging, please ensure Selenium is enabled in your Monadic Chat settings.

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

    unless debugger.send(:selenium_available?)
      return {
        success: false,
        error: 'Selenium container is not running',
        hint: 'Please ensure Selenium is enabled in your Monadic Chat settings.',
        project_name: context[:project_name],
        html_path: context[:html_path]
      }
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
    @last_diagnosis = diagnosis
    ensure_context_hash[:last_diagnosis] = diagnosis
  end

  def current_diagnosis
    diagnosis = @last_diagnosis
    return diagnosis if diagnosis

    ctx = ensure_context_hash
    ctx[:last_diagnosis] || ctx['last_diagnosis']
  end

  def diagnosis_expired?(diagnosis)
    timestamp = fetch_from_hash(diagnosis, :timestamp)
    return true unless timestamp.is_a?(Time)

    (Time.now - timestamp) > DIAGNOSIS_TIMEOUT
  end

  def clear_diagnosis_state
    @last_diagnosis = nil
    ctx = ensure_context_hash
    ctx.delete(:last_diagnosis)
    ctx.delete('last_diagnosis')
  end

  def resolve_project_context(params)
    spec = normalize_spec(params)
    manual_path = fetch_from_hash(spec, :project_path) || fetch_from_hash(spec, :project_dir)
    manual_path = manual_path.to_s.strip

    project_name = fetch_from_hash(spec, :name)&.to_s&.strip

    if manual_path && !manual_path.empty?
      expanded_path = File.expand_path(manual_path)

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

  def ensure_context_hash
    @context = {} unless @context.is_a?(Hash)
    @context
  end

  def format_ms(value)
    value ? "#{value}ms" : 'n/a'
  end
end
