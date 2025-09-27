# frozen_string_literal: true

require_relative 'auto_forge'
require_relative 'auto_forge_utils'
require_relative '../../lib/monadic/agents/gpt5_codex_agent'

# Tool methods for AutoForge MDSL application
# Uses GPT-5 for orchestration and GPT-5-Codex for code generation
module AutoForgeTools
  include MonadicHelper
  include Monadic::Agents::GPT5CodexAgent

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
end