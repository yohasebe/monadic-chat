# Add required utilities
require_relative 'utils/fa_icons'

# Load auto-completer if available
begin
  require_relative 'dsl/tool_auto_completer'
rescue LoadError
  # Auto-completer not available, continue without it
end

# Add the app method to top-level scope to enable the simplified DSL
def app(name, &block)
  MonadicDSL.app(name, &block)
end

module MonadicDSL
  # Base class for application state management

  # The following setting parameters are available for defining applications:
  #
  # - image: Enables image handling and attachments in the UI
  # - pdf: Enables PDF document upload, parsing, and interaction
  # - easy_submit: Enables submitting messages on Enter key (without needing to click Send)
  # - auto_speech: Enables automatic text-to-speech for assistant messages
  # - initiate_from_assistant: Allows assistant to proactively send follow-up messages
  # - mermaid: Enables Mermaid diagram rendering and interaction for flowcharts and diagrams
  # - mathjax: Enables mathematical notation rendering using MathJax library
  # - abc: Enables ABC music notation rendering and playback for music composition
  # - sourcecode: Enables enhanced source code highlighting and formatting (code_highlight)
  # - toggle: Controls collapsible sections for code blocks and other content
  # - tools: Defines function-calling capabilities available to the model
  # - image_generation: Enables AI image generation within the conversation
  # - monadic: Enables monadic mode for structured JSON responses and special rendering
  # - websearch: Enables web search functionality for retrieving external information (web_search)
  # - jupyter_access: Enables access to Jupyter notebooks in the conversation (jupyter)
  # - temperature: Controls randomness in model responses (0.0-2.0)
  # - model: Specifies which AI model to use for this app
  # - group: Groups apps by provider (e.g., "OpenAI", "Anthropic", "Google")
  # - app_name: Defines the display name of the application
  # - description: Provides UI description text for the application
  # - icon: Specifies the FontAwesome icon to use for the app
  # - initial_prompt: Sets the system prompt/instructions for the model
  # - disabled: Indicates if the app should be disabled (e.g., when API key is missing)
  # - reasoning_effort: Controls the depth of reasoning (e.g., "high")
  # - context_size: Controls the context window size for the conversation
  # - max_tokens: Specifies the maximum number of tokens to generate (max_output_tokens)
  #
  # Note: Some parameters support aliases (shown in parentheses) for backward compatibility:
  # - sourcecode (code_highlight)
  # - websearch (web_search)
  # - jupyter (jupyter_access)
  # - max_tokens (max_output_tokens)

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
      
      # After creating the class from MDSL, check for and load corresponding tools file
      base_name = File.basename(@file, '.*')
      dir_path = File.dirname(@file)
      
      # Remove provider suffix (e.g., _openai, _claude) to get base app name
      app_base_name = base_name.sub(/_\w+$/, '')
      tools_file = File.join(dir_path, "#{app_base_name}_tools.rb")
      
      if File.exist?(tools_file)
        # Load the tools file to add methods to the class
        require tools_file
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
  end

  class AppState
    attr_reader :name
    attr_accessor :settings, :features, :ui, :prompts
    
    def initialize(name)
      @name = name
      @settings = {}
      @features = {}
      @ui = {}
      @prompts = {}
    end
    
    # Bind operation for state transformation

    def bind(&block)
      Result.new(block.call(self))
    rescue => e
      Result.new(nil, e)
    end
    
    # Map operation for value transformation

    def map(&block)
      bind { |state| self.class.new(block.call(state)) }
    end
    
    # Validate the current state

    def validate!
      raise ValidationError, "Name is required" unless @name
      raise ValidationError, "Settings are required" if @settings.empty?
      raise ValidationError, "Provider is required" unless @settings[:provider]
      true
    end
  end
  
  # Result monad for error handling

  class Result
    attr_reader :value, :error
    
    def initialize(value, error = nil)
      @value = value
      @error = error
    end
    
    def bind(&block)
      return self if @error
      begin
        block.call(@value)
      rescue => e
        Result.new(nil, e)
      end
    end
    
    def map(&block)
      bind { |value| Result.new(block.call(value)) }
    end
    
    def success?
      !@error
    end
  end
  
  
  # Base class for tool definitions with provider-specific validation

  class ToolDefinition
    attr_reader :name, :description, :parameters, :required, :enum_values
    
    def initialize(name, description)
      @name = name
      @description = description
      @parameters = {}
      @required = []
      @enum_values = {}
    end

    # Define a parameter with optional enum values and array items

    def parameter(name, type, description, required: false, enum: nil, items: nil)
      @parameters[name] = {
        type: type,
        description: description
      }
      @parameters[name][:items] = items if items
      @enum_values[name] = enum if enum
      @required << name if required
      self
    end
    
    # Provider-specific validation

    def validate_for_provider(provider)
      case provider
      when :gemini
        validate_gemini_requirements
      when :openai
        validate_openai_requirements
      when :anthropic
        validate_anthropic_requirements
      when :cohere
        validate_cohere_requirements
      when :mistral
        validate_mistral_requirements
      when :deepseek
        validate_deepseek_requirements
      when :perplexity
        validate_perplexity_requirements
      when :xai
        validate_grok_requirements
      end
    end
    
    private
    
    def validate_gemini_requirements
      # Gemini-specific validation

      raise ValidationError, "Invalid tool format for Gemini" unless valid_for_gemini?
    end
    
    def validate_openai_requirements
      # OpenAI-specific validation

      raise ValidationError, "Invalid tool format for OpenAI" unless valid_for_openai?
    end
    
    def validate_anthropic_requirements
      # Anthropic-specific validation

      raise ValidationError, "Invalid tool format for Anthropic" unless valid_for_anthropic?
    end
    
    def validate_cohere_requirements
      # Cohere-specific validation

      raise ValidationError, "Invalid tool format for Cohere" unless valid_for_cohere?
    end
    
    def validate_mistral_requirements
      # Mistral-specific validation

      raise ValidationError, "Invalid tool format for Mistral" unless valid_for_mistral?
    end
    
    def validate_deepseek_requirements
      # DeepSeek-specific validation

      raise ValidationError, "Invalid tool format for DeepSeek" unless valid_for_deepseek?
    end

    def validate_perplexity_requirements
      # Perplexity-specific validation

      raise ValidationError, "Invalid tool format for Perplexity" unless valid_for_perplexity?
    end

    def validate_grok_requirements
      # Grok-specific validation

      raise ValidationError, "Invalid tool format for Grok" unless valid_for_grok?
    end

    def valid_for_openai?
      # Implement OpenAI-specific validation logic

      true
    end
    
    def valid_for_grok?
      # Implement Grok-specific validation logic

      true
    end

    def valid_for_perplexity?
      # Implement Perplexity-specific validation logic

      true
    end


    def valid_for_gemini?
      # Implement Gemini-specific validation logic

      true
    end
    
    def valid_for_anthropic?
      # Implement Anthropic-specific validation logic

      true
    end
    
    def valid_for_cohere?
      # Implement Cohere-specific validation logic

      true
    end
    
    def valid_for_mistral?
      # Implement Mistral-specific validation logic

      true
    end
    
    def valid_for_deepseek?
      # Implement DeepSeek-specific validation logic

      true
    end
  end

  # Provider-specific tool formatters

  module ToolFormatters
    class OpenAIFormatter
      def format(tool)
        {
          type: "function",
          function: {
            name: tool.name,
            description: tool.description,
            parameters: {
              type: "object",
              properties: format_properties(tool),
              required: tool.required,
              additionalProperties: false
            }
          },
          strict: true
        }
      end
      
      private
      
      def format_properties(tool)
        props = {}
        tool.parameters.each do |name, param|
          props[name] = {
            type: param[:type],
            description: param[:description]
          }
          
          # Add items property for array types (required by OpenAI)
          if param[:type] == "array"
            props[name][:items] = param[:items] || { type: "object" }
          end
          
          props[name][:enum] = tool.enum_values[name] if tool.enum_values[name]
        end
        props
      end
    end

    class AnthropicFormatter
      def format(tool)
        {
          name: tool.name,
          description: tool.description,
          input_schema: {
            type: "object",
            properties: format_properties(tool),
            required: tool.required
          }
        }
      end
      
      private
      
      def format_properties(tool)
        props = {}
        tool.parameters.each do |name, param|
          props[name] = {
            type: param[:type],
            description: param[:description]
          }
          props[name][:enum] = tool.enum_values[name] if tool.enum_values[name]
        end
        props
      end
    end
    
    class CohereFormatter
      def format(tool)
        {
          type: "function",
          function: {
            name: tool.name,
            description: tool.description,
            parameters: {
              type: "object",
              properties: format_properties(tool),
              required: tool.required
            }
          }
        }
      end
      
      private
      
      def format_properties(tool)
        properties = {}
        tool.parameters.each do |name, param|
          properties[name] = {
            type: param[:type],
            description: param[:description]
          }
          properties[name][:enum] = tool.enum_values[name] if tool.enum_values[name]
        end
        properties
      end
    end
    
    class GeminiFormatter
      def format(tool)
        {
          name: tool.name,
          description: tool.description,
          parameters: {
            type: "object",
            properties: format_properties(tool),
            required: tool.required
          }
        }
      end

      private
      
      def format_properties(tool)
        props = {}
        tool.parameters.each do |name, param|
          props[name] = {
            type: param[:type],
            description: param[:description]
          }
          # Gemini-specific enum handling

          if tool.enum_values[name]
            props[name][:enum] = tool.enum_values[name]
          end
        end
        props
      end
    end

    class MistralFormatter
      def format(tool)
        {
          type: "function",
          function: {
            name: tool.name,
            description: tool.description,
            parameters: {
              type: "object",
              properties: format_properties(tool),
              required: tool.required
            }
          }
        }
      end
      
      private
      
      def format_properties(tool)
        props = {}
        tool.parameters.each do |name, param|
          props[name] = {
            type: param[:type],
            description: param[:description]
          }
          props[name][:enum] = tool.enum_values[name] if tool.enum_values[name]
        end
        props
      end
    end
    
    class DeepSeekFormatter
      def format(tool)
        {
          type: "function",
          function: {
            name: tool.name,
            description: tool.description,
            parameters: {
              type: "object",
              properties: format_properties(tool),
              required: tool.required
            }
          }
        }
      end

      private
      
      def format_properties(tool)
        props = {}
        tool.parameters.each do |name, param|
          props[name] = {
            type: param[:type],
            description: param[:description]
          }
          props[name][:enum] = tool.enum_values[name] if tool.enum_values[name]
        end
        props
      end
    end

    class PerplexityFormatter
      def format(tool)
        {
          type: "function",
          function: {
            name: tool.name,
            description: tool.description,
            parameters: {
              type: "object",
              properties: format_properties(tool),
              required: tool.required
            }
          }
        }
      end
      
      private
      
      def format_properties(tool)
        props = {}
        tool.parameters.each do |name, param|
          props[name] = {
            type: param[:type],
            description: param[:description]
          }
          props[name][:enum] = tool.enum_values[name] if tool.enum_values[name]
        end
        props
      end
    end

    class GrokFormatter
      def format(tool)
        {
          type: "function",
          function: {
            name: tool.name,
            description: tool.description,
            parameters: {
              type: "object",
              properties: format_properties(tool),
              required: tool.required,
              additionalProperties: false
            }
          },
          strict: true
        }
      end
      
      private
      
      def format_properties(tool)
        props = {}
        tool.parameters.each do |name, param|
          props[name] = {
            type: param[:type],
            description: param[:description]
          }
          props[name][:enum] = tool.enum_values[name] if tool.enum_values[name]
        end
        props
      end
    end
  end

  # Tool configuration DSL with provider-specific handling

  class ToolConfiguration
    FORMATTERS = {
      openai: ToolFormatters::OpenAIFormatter,
      anthropic: ToolFormatters::AnthropicFormatter,
      claude: ToolFormatters::AnthropicFormatter,
      cohere: ToolFormatters::CohereFormatter,
      gemini: ToolFormatters::GeminiFormatter,
      mistral: ToolFormatters::MistralFormatter,
      deepseek: ToolFormatters::DeepSeekFormatter,
      perplexity: ToolFormatters::PerplexityFormatter,
      xai: ToolFormatters::GrokFormatter
    }
    
    PROVIDER_WRAPPERS = {
      gemini: ->(tools) { { function_declarations: tools } },
      default: ->(tools) { tools }
    }
    
    def initialize(state, provider)
      @state = state
      @provider = provider
      @tools = []
      @formatter = FORMATTERS[provider].new
    end
    
    # Define a new tool

    def define_tool(name, description, &block)
      tool = ToolDefinition.new(name, description)
      tool.instance_eval(&block) if block_given?
      tool.validate_for_provider(@provider)
      @tools << tool
      tool
    end

    # Auto-complete tools from Ruby implementation files
    def auto_complete_from_ruby_files
      # Load the auto-completer if available
      return unless defined?(MonadicDSL::ToolAutoCompleter)
      
      # Debug: print that auto-completion is running
      puts "[DEBUG] Auto-completion triggered" if ENV['MDSL_AUTO_COMPLETE'] == 'debug'
      
      # Get the current MDSL file path from the call stack
      mdsl_file = find_current_mdsl_file
      puts "[DEBUG] Found MDSL file: #{mdsl_file || 'nil'}" if ENV['MDSL_AUTO_COMPLETE'] == 'debug'
      
      # If not found in call stack, try to infer from app name
      if mdsl_file.nil? && @state.name
        puts "[DEBUG] App name: #{@state.name}" if ENV['MDSL_AUTO_COMPLETE'] == 'debug'
        mdsl_file = infer_mdsl_file_from_app_name(@state.name)
        puts "[DEBUG] Inferred MDSL file: #{mdsl_file || 'nil'}" if ENV['MDSL_AUTO_COMPLETE'] == 'debug'
      else
        puts "[DEBUG] No app name available: #{@state.name || 'nil'}" if ENV['MDSL_AUTO_COMPLETE'] == 'debug'
      end
      
      return unless mdsl_file
      
      completer = MonadicDSL::ToolAutoCompleter.new
      analysis = completer.analyze_single_file(mdsl_file)
      
      # Auto-complete missing tool definitions
      auto_completed_tools = []
      analysis[:missing_definitions].each do |tool_name|
        # Find Ruby implementation file
        ruby_file = analysis[:ruby_files].find { |f| File.read(f).include?("def #{tool_name}") }
        next unless ruby_file
        
        # Generate tool definition
        tool_def = completer.send(:generate_single_tool_definition, tool_name, ruby_file)
        next unless tool_def
        
        # Create and add the tool
        tool = ToolDefinition.new(tool_def[:name], tool_def[:description])
        tool_def[:parameters].each do |param|
          tool.parameter(param[:name].to_sym, param[:type], param[:description], required: param[:required])
        end
        
        @tools << tool
        auto_completed_tools << tool_def
      end
      
      # Write auto-completed definitions to MDSL file if any were found
      if auto_completed_tools.any?
        auto_complete_mode = ENV['MDSL_AUTO_COMPLETE'] || 'true'
        
        case auto_complete_mode.downcase
        when 'false'
          # Do nothing - auto-completion disabled
        when 'debug'
          # Write with detailed logging
          write_auto_completed_tools_to_mdsl(mdsl_file, auto_completed_tools, debug: true)
        else
          # Default: write without detailed logging (true or any other value)
          write_auto_completed_tools_to_mdsl(mdsl_file, auto_completed_tools, debug: false)
        end
      end
    end
    
    # Convert tools to provider-specific format

    def to_h
      formatted_tools = @tools.map { |t| @formatter.format(t) }
      wrapper = PROVIDER_WRAPPERS[@provider] || PROVIDER_WRAPPERS[:default]
      wrapper.call(formatted_tools)
    end
    
    private
    
    # Find the current MDSL file being processed from call stack
    def find_current_mdsl_file
      puts "[DEBUG] Searching call stack for MDSL file..." if ENV['MDSL_AUTO_COMPLETE'] == 'debug'
      
      caller_locations.each_with_index do |location, index|
        path = location.absolute_path
        puts "[DEBUG] Call #{index}: #{path}" if ENV['MDSL_AUTO_COMPLETE'] == 'debug'
        
        if path&.end_with?('.mdsl')
          puts "[DEBUG] Found MDSL file: #{path}" if ENV['MDSL_AUTO_COMPLETE'] == 'debug'
          return path
        end
      end
      
      puts "[DEBUG] No MDSL file found in call stack" if ENV['MDSL_AUTO_COMPLETE'] == 'debug'
      nil
    end
    
    # Infer MDSL file path from app name
    def infer_mdsl_file_from_app_name(app_name)
      puts "[DEBUG] Starting inference for app: #{app_name}" if ENV['MDSL_AUTO_COMPLETE'] == 'debug'
      
      # Extract provider suffix from app name to match the correct MDSL file
      provider_suffix = nil
      provider_patterns = {
        /OpenAI$/ => 'openai',
        /Claude$/ => 'claude',
        /Anthropic$/ => 'claude',  # Anthropic maps to claude
        /Gemini$/ => 'gemini',
        /Google$/ => 'gemini',     # Google maps to gemini
        /Mistral$/ => 'mistral',
        /Cohere$/ => 'cohere',
        /Perplexity$/ => 'perplexity',
        /Grok$/ => 'grok',
        /XAI$/ => 'grok',          # XAI maps to grok
        /DeepSeek$/ => 'deepseek'
      }
      
      app_base = app_name.dup
      provider_patterns.each do |pattern, suffix|
        if app_name.match?(pattern)
          provider_suffix = suffix
          app_base = app_name.gsub(pattern, '')
          break
        end
      end
      
      puts "[DEBUG] App base after provider removal: #{app_base}, provider suffix: #{provider_suffix}" if ENV['MDSL_AUTO_COMPLETE'] == 'debug'
      
      # Convert to snake_case
      base_name = app_base.gsub(/([A-Z])/, '_\1').downcase.gsub(/^_/, '')
      puts "[DEBUG] Base name after snake_case conversion: #{base_name}" if ENV['MDSL_AUTO_COMPLETE'] == 'debug'
      
      # Try to find the apps directory (including user-defined plugins)
      # Use the same pattern as lib/monadic.rb for environment detection
      user_plugins_dir = if defined?(IN_CONTAINER) && IN_CONTAINER
                           "/monadic/data/plugins"
                         else
                           Dir.home + "/monadic/data/plugins"
                         end
      
      apps_dirs = [
        File.join(Dir.pwd, "apps"),
        File.join(Dir.pwd, "docker", "services", "ruby", "apps"),
        File.join(__dir__, "..", "..", "apps"),
        user_plugins_dir
      ]
      
      puts "[DEBUG] Searching in directories: #{apps_dirs}" if ENV['MDSL_AUTO_COMPLETE'] == 'debug'
      
      apps_dirs.each do |apps_dir|
        puts "[DEBUG] Checking apps directory: #{apps_dir} (exists: #{File.directory?(apps_dir)})" if ENV['MDSL_AUTO_COMPLETE'] == 'debug'
        next unless File.directory?(apps_dir)
        
        app_dir = File.join(apps_dir, base_name)
        puts "[DEBUG] Checking app directory: #{app_dir} (exists: #{File.directory?(app_dir)})" if ENV['MDSL_AUTO_COMPLETE'] == 'debug'
        next unless File.directory?(app_dir)
        
        # If we have a provider suffix, look for the specific MDSL file first
        if provider_suffix
          specific_mdsl = File.join(app_dir, "#{base_name}_#{provider_suffix}.mdsl")
          puts "[DEBUG] Looking for specific MDSL: #{specific_mdsl}" if ENV['MDSL_AUTO_COMPLETE'] == 'debug'
          if File.exist?(specific_mdsl)
            puts "[DEBUG] Found specific MDSL file: #{specific_mdsl}" if ENV['MDSL_AUTO_COMPLETE'] == 'debug'
            return specific_mdsl
          end
        end
        
        # Fallback: Look for any MDSL files matching the app name pattern
        mdsl_pattern = "#{base_name}_*.mdsl"
        mdsl_files = Dir.glob(File.join(app_dir, mdsl_pattern))
        puts "[DEBUG] MDSL pattern: #{mdsl_pattern}, found files: #{mdsl_files}" if ENV['MDSL_AUTO_COMPLETE'] == 'debug'
        
        # Return the first matching MDSL file
        if mdsl_files.any?
          puts "[DEBUG] Returning MDSL file: #{mdsl_files.first}" if ENV['MDSL_AUTO_COMPLETE'] == 'debug'
          return mdsl_files.first
        end
      end
      
      puts "[DEBUG] No MDSL file found for app: #{app_name}" if ENV['MDSL_AUTO_COMPLETE'] == 'debug'
      nil
    end
    
    # Write auto-completed tool definitions to MDSL file
    def write_auto_completed_tools_to_mdsl(mdsl_file, auto_completed_tools, debug: false)
      return unless File.exist?(mdsl_file)
      
      content = File.read(mdsl_file)
      
      # Find the tools do...end block with proper nesting support
      # This regex uses a more specific pattern to match the tools block
      # It looks for 'tools do' and captures content until it finds an 'end' at the same indentation level
      # The fourth capture group now captures everything AFTER the tools block end
      tools_regex = /(.*?^(\s*)tools\s+do\s*\n)(.*?)(^\2end)(.*)/m
      tools_block_match = content.match(tools_regex)
      
      if !tools_block_match
        # Fallback to simpler pattern if the indentation-based one fails
        # This one counts nested blocks to find the matching end
        tools_start_index = content.index(/^\s*tools\s+do\s*$/m)
        return unless tools_start_index
        
        # Find the matching 'end' by counting nesting levels
        indent_match = content[tools_start_index..].match(/^(\s*)tools/)
        indent = indent_match[1]
        
        # Extract the part after 'tools do'
        after_tools_do = content[(tools_start_index + content[tools_start_index..].index("\n") + 1)..]
        
        # Find the matching end at the same indentation level
        lines = after_tools_do.lines
        nesting_level = 1
        tools_content_lines = []
        remaining_lines = []
        found_end = false
        
        lines.each_with_index do |line, idx|
          if !found_end
            # Check for nested do/end blocks
            if line.match(/\bdo\s*$/)
              nesting_level += 1
            elsif line.match(/^#{Regexp.escape(indent)}end\b/) && nesting_level == 1
              # Found the matching end for tools block
              found_end = true
              remaining_lines = lines[idx..]
            elsif line.match(/\bend\b/)
              nesting_level -= 1
            end
            
            tools_content_lines << line unless found_end
          end
        end
        
        return unless found_end
        
        before_tools = content[0...tools_start_index] + indent + "tools do\n"
        current_tools = tools_content_lines.join
        after_tools = remaining_lines.join
      else
        before_tools = tools_block_match[1]
        current_tools = tools_block_match[3]
        tools_end = tools_block_match[4]
        after_tools = tools_block_match[5]
      end
      
      # Generate auto-completed tool definitions
      auto_generated_definitions = generate_tool_definitions_text(auto_completed_tools)
      
      # Check if current tools section is empty or only contains comments
      tools_section_empty = current_tools.strip.empty? || current_tools.strip.start_with?('#')
      
      if tools_section_empty
        # Replace empty tools section with auto-generated definitions
        new_tools_section = "    # Auto-generated tool definitions from Ruby implementation\n" + auto_generated_definitions
      else
        # Append to existing tools
        new_tools_section = current_tools.rstrip + "\n\n    # Auto-generated tool definitions\n" + auto_generated_definitions
      end
      
      # Reconstruct the file content
      if tools_block_match
        # We have the tools_end captured separately
        new_content = before_tools + new_tools_section + "\n" + tools_end + after_tools
      else
        # Fallback case - add end with proper indentation
        new_content = before_tools + new_tools_section + "\n#{indent}end" + after_tools
      end
      
      # Write back to file with backup
      backup_file = "#{mdsl_file}.backup.#{Time.now.strftime('%Y%m%d_%H%M%S')}"
      File.write(backup_file, content)
      File.write(mdsl_file, new_content)
      
      # Always show basic info message
      puts "[INFO] Auto-completed #{auto_completed_tools.size} tool(s) in #{File.basename(mdsl_file)}"
      
      if debug
        puts "[DEBUG] Tools added: #{auto_completed_tools.map { |t| t[:name] }.join(', ')}" if ENV['MDSL_AUTO_COMPLETE'] == 'debug'
        puts "[DEBUG] MDSL file: #{mdsl_file}" if ENV['MDSL_AUTO_COMPLETE'] == 'debug'
        puts "[DEBUG] Backup created: #{File.basename(backup_file)}" if ENV['MDSL_AUTO_COMPLETE'] == 'debug'
      end
    rescue => e
      puts "[ERROR] Failed to write auto-completed tools to #{mdsl_file}: #{e.message}"
      puts "[DEBUG] Error details: #{e.backtrace.first(3).join('\n')}" if debug
    end
    
    # Generate MDSL tool definition text from tool definitions
    def generate_tool_definitions_text(tool_definitions)
      definitions = []
      
      tool_definitions.each do |tool_def|
        definition_lines = ["    define_tool \"#{tool_def[:name]}\", \"#{tool_def[:description]}\" do"]
        
        tool_def[:parameters].each do |param|
          required_text = param[:required] ? ", required: true" : ""
          definition_lines << "      parameter :#{param[:name]}, \"#{param[:type]}\", \"#{param[:description]}\"#{required_text}"
        end
        
        definition_lines << "    end"
        definitions << definition_lines.join("\n")
      end
      
      definitions.join("\n\n")
    end
    
    # Provider-specific settings

    def provider_specific_settings
      case @provider
      when :gemini
        @state.settings[:gemini_specific] = {
          parallel_calling: true,
          safety_settings: default_safety_settings
        }
      when :anthropic
        @state.settings[:anthropic_specific] = {
        }
      when :cohere
        @state.settings[:cohere_specific] = {
        }
      when :mistral
        @state.settings[:mistral_specific] = {
        }
      when :deepseek
        @state.settings[:deepseek_specific] = {
        }
      when :perplexity
        @state.settings[:perplexity_specific] = {
        }
      when :xai
        @state.settings[:xai_specific] = {
        }
      end
    end
    
    private
    
    def default_safety_settings
      {
        harassment: "block_none",
        hate_speech: "block_none",
        sexually_explicit: "block_none",
        dangerous_content: "block_none"
      }
    end
  end


  # Custom error classes

  class ValidationError < StandardError; end
  class ConfigurationError < StandardError; end
  
  # Module methods
  
  # App definition method
  def self.app(name, &block)
    state = AppState.new(name.gsub(/\s+/, ''))
    # Always store original name as display_name to ensure consistency
    state.settings[:display_name] = name
    
    # Initialize default values
    state.features = {}
    state.settings[:provider] = "OpenAI"
    state.settings[:model] = "gpt-4.1"
    state.settings[:temperature] = 0.7
    
    # Process the DSL block
    app_def = SimplifiedAppDefinition.new(state)
    app_def.instance_eval(&block)
    
    # Debug the state
    puts "After DSL eval: #{state.name}, display_name: #{state.settings[:display_name]}" if defined?(CONFIG) && CONFIG["EXTRA_LOGGING"]
    
    convert_to_class(state)
    state
  end
  
  # Simplified app definition class
  class SimplifiedAppDefinition
    def initialize(state)
      @state = state
    end
    
    def description(text)
      @state.ui[:description] = text
    end
    
    def icon(name)
      @state.ui[:icon] = IconHelper.to_html(name)
    end
    
    def app_name(name)
      @state.settings[:app_name] = name
    end
    
    def display_name(name)
      @state.settings[:display_name] = name
    end
    
    def system_prompt(text)
      @state.prompts[:initial] = text
    end
    
    # Module include support
    def include_modules(*modules)
      @state.settings[:include_modules] = modules.map(&:to_s)
    end
    
    def llm(&block)
      LLMConfiguration.new(@state).instance_eval(&block)
    end
    
    def features(&block)
      SimplifiedFeatureConfiguration.new(@state).instance_eval(&block)
    end
    
    def tools(&block)
      # Convert provider to symbol
      provider = @state.settings[:provider].to_s.downcase.to_sym
      
      tool_config = ToolConfiguration.new(@state, provider)
      tool_config.instance_eval(&block) if block_given?
      
      # Auto-complete tools from Ruby implementation files
      tool_config.auto_complete_from_ruby_files
      
      @state.settings[:tools] = tool_config.to_h
    end
  end
  
  # LLM Configuration for simplified syntax
  class LLMConfiguration
    # Map newer parameter names to standard ones
    PARAMETER_MAP = {
      max_output_tokens: :max_tokens
    }
    
    def initialize(state)
      @state = state
    end
    
    def provider(value)
      @state.settings[:provider] = value
    end
    
    def model(value = nil)
      provider_name = @state.settings[:provider].to_s.downcase
      provider_env_var = nil

      # Determine the environment variable based on provider
      if provider_name.include?("anthropic") || provider_name.include?("claude")
        provider_env_var = "ANTHROPIC_DEFAULT_MODEL"
      elsif provider_name.include?("openai") || provider_name.include?("gpt")
        provider_env_var = "OPENAI_DEFAULT_MODEL"
      elsif provider_name.include?("cohere") || provider_name.include?("command")
        provider_env_var = "COHERE_DEFAULT_MODEL"
      elsif provider_name.include?("gemini") || provider_name.include?("google")
        provider_env_var = "GEMINI_DEFAULT_MODEL"
      elsif provider_name.include?("mistral")
        provider_env_var = "MISTRAL_DEFAULT_MODEL"
      elsif provider_name.include?("grok") || provider_name.include?("xai")
        provider_env_var = "GROK_DEFAULT_MODEL"
      elsif provider_name.include?("perplexity")
        provider_env_var = "PERPLEXITY_DEFAULT_MODEL"
      elsif provider_name.include?("deepseek")
        provider_env_var = "DEEPSEEK_DEFAULT_MODEL"
      end

      # If a value is provided, it takes precedence over environment variables
      if value
        @state.settings[:model] = value
      # Otherwise, try to use environment variable if available
      elsif provider_env_var && ENV[provider_env_var]
        @state.settings[:model] = ENV[provider_env_var]
      end
    end
    
    def temperature(value)
      @state.settings[:temperature] = value
    end
    
    def max_tokens(value)
      @state.settings[:max_tokens] = value
    end
    
    def max_output_tokens(value)
      # Alias for max_tokens
      max_tokens(value)
    end
    
    def reasoning_effort(value)
      @state.settings[:reasoning_effort] = value
    end
    
    def presence_penalty(value)
      @state.settings[:presence_penalty] = value
    end
    
    def frequency_penalty(value)
      @state.settings[:frequency_penalty] = value
    end
    
    def response_format(value)
      @state.settings[:response_format] = value
    end
    
    def context_size(value)
      @state.settings[:context_size] = value
    end
    
    def method_missing(method_name, *args)
      if PARAMETER_MAP.key?(method_name)
        send(PARAMETER_MAP[method_name], *args)
      else
        super
      end
    end
    
    def respond_to_missing?(method_name, include_private = false)
      PARAMETER_MAP.key?(method_name) || super
    end
  end
  
  # Simplified Feature Configuration
  class SimplifiedFeatureConfiguration
    # Map newer feature names to old ones where needed
    FEATURE_MAP = {
      code_highlight: :sourcecode,
      web_search: :websearch,
      jupyter_access: :jupyter
    }
    
    def initialize(state)
      @state = state
    end
    
    def method_missing(method_name, *args)
      # Default all called methods to true, handle special cases
      value = args.first.nil? ? true : args.first
      
      feature_name = FEATURE_MAP[method_name] || method_name
      @state.features[feature_name] = value
    end
    
    def respond_to_missing?(method_name, include_private = false)
      true
    end
  end

  # Provider configuration for standardizing provider-related settings
  class ProviderConfig
    # Provider information mapping
    PROVIDER_INFO = {
      # Anthropic/Claude
      "anthropic" => {
        helper_module: 'ClaudeHelper',
        api_key: 'ANTHROPIC_API_KEY',
        display_group: 'Anthropic',
        aliases: ['claude', 'anthropicclaude']
      },
      # Google/Gemini
      "gemini" => {
        helper_module: 'GeminiHelper',
        api_key: 'GEMINI_API_KEY',
        display_group: 'Google',
        aliases: ['google', 'googlegemini']
      },
      # Cohere
      "cohere" => {
        helper_module: 'CohereHelper',
        api_key: 'COHERE_API_KEY',
        display_group: 'Cohere',
        aliases: ['commandr', 'coherecommandr']
      },
      # Mistral
      "mistral" => {
        helper_module: 'MistralHelper',
        api_key: 'MISTRAL_API_KEY',
        display_group: 'Mistral',
        aliases: ['mistralai']
      },
      # DeepSeek
      "deepseek" => {
        helper_module: 'DeepSeekHelper',
        api_key: 'DEEPSEEK_API_KEY',
        display_group: 'DeepSeek',
        aliases: ['deep seek']
      },
      # Perplexity
      "perplexity" => {
        helper_module: 'PerplexityHelper',
        api_key: 'PERPLEXITY_API_KEY',
        display_group: 'Perplexity',
        aliases: []
      },
      # XAI/Grok
      "xai" => {
        helper_module: 'GrokHelper',
        api_key: 'XAI_API_KEY',
        display_group: 'xAI',
        aliases: ['grok', 'xaigrok']
      },
      # OpenAI (default)
      "openai" => {
        helper_module: 'OpenAIHelper',
        api_key: 'OPENAI_API_KEY',
        display_group: 'OpenAI',
        aliases: []
      }
    }
    
    # Constructor
    def initialize(provider_name)
      @provider_name = provider_name.to_s.downcase.gsub(/[\s\-]+/, "")
      @config = find_provider_config
    end
    
    # Get helper module name
    def helper_module
      @config[:helper_module]
    end
    
    # Get API key environment variable name
    def api_key_name
      @config[:api_key]
    end
    
    # Get display group name
    def display_group
      @config[:display_group]
    end
    
    # Get standard provider key
    def standard_key
      @config[:standard_key] || @provider_name
    end
    
    # Get model list using the appropriate helper
    def model_list
      if Object.const_defined?(@config[:helper_module])
        helper_class = Object.const_get(@config[:helper_module])
        if helper_class.respond_to?(:list_models)
          return helper_class.list_models
        end
      end
      []
    end
    
    private
    
    # Find the provider configuration based on name or aliases
    def find_provider_config
      # Direct match
      PROVIDER_INFO.each do |key, config|
        return config.merge(standard_key: key) if key == @provider_name
      end
      
      # Check aliases
      PROVIDER_INFO.each do |key, config|
        return config.merge(standard_key: key) if config[:aliases].include?(@provider_name)
      end
      
      # Default to OpenAI if no match
      PROVIDER_INFO["openai"]
    end
  end

  # Helper method to convert simplified state to class
  def self.convert_to_class(state)
    # Get standardized provider configuration
    provider_config = ProviderConfig.new(state.settings[:provider])
    helper_module = provider_config.helper_module
    
    # Get model list using helper module - simpler one-line version to avoid syntax errors
    model_list_code = "defined?(#{helper_module}) ? #{helper_module}.list_models : []"

    # Debug the state
    puts "Converting class: #{state.name}, app_name: #{state.settings[:app_name]}" if defined?(CONFIG) && CONFIG["EXTRA_LOGGING"]

    # Make sure app_name is set from either settings or features
    app_name = state.settings[:app_name] || state.name
    
    # Use display_name if provided, otherwise use app_name
    display_name = state.settings[:display_name] || app_name

    # Get distributed mode from CONFIG hash (loaded from .env file) instead of environment variable
    distributed_mode = defined?(CONFIG) && CONFIG["DISTRIBUTED_MODE"] ? CONFIG["DISTRIBUTED_MODE"] : "off"
    
    # Check if this app should be disabled in server mode due to security concerns
    jupyter_disabled_in_server = distributed_mode == "server" && 
      (state.features[:jupyter] == true || 
       state.features[:jupyter_access] == true || 
       state.features[:jupyter] == "true" || 
       state.features[:jupyter_access] == "true")
    
    # Get appropriate environment variable name based on provider
    provider_name = state.settings[:provider].to_s.downcase
    provider_env_var = nil
    
    if provider_name.include?("anthropic") || provider_name.include?("claude")
      provider_env_var = "ANTHROPIC_DEFAULT_MODEL"
    elsif provider_name.include?("openai") || provider_name.include?("gpt")
      provider_env_var = "OPENAI_DEFAULT_MODEL"
    elsif provider_name.include?("cohere") || provider_name.include?("command")
      provider_env_var = "COHERE_DEFAULT_MODEL"
    elsif provider_name.include?("gemini") || provider_name.include?("google")
      provider_env_var = "GEMINI_DEFAULT_MODEL"
    elsif provider_name.include?("mistral")
      provider_env_var = "MISTRAL_DEFAULT_MODEL"
    elsif provider_name.include?("grok") || provider_name.include?("xai")
      provider_env_var = "GROK_DEFAULT_MODEL"
    elsif provider_name.include?("perplexity")
      provider_env_var = "PERPLEXITY_DEFAULT_MODEL"
    elsif provider_name.include?("deepseek")
      provider_env_var = "DEEPSEEK_DEFAULT_MODEL"
    end

    # Determine model value for class definition
    model_value = if state.settings[:model]
                    # Use model from MDSL file if specified
                    state.settings[:model].inspect
                  elsif provider_env_var
                    # Use environment variable with string interpolation in generated code
                    # Include provider-specific default fallback value if no env var
                    default_model = case provider_name
                                    when /anthropic|claude/ then "claude-3-5-sonnet-20241022"
                                    when /openai|gpt/ then "gpt-4.1"
                                    when /cohere|command/ then "command-r-plus"
                                    when /gemini|google/ then "gemini-2.0-flash"
                                    when /mistral/ then "mistral-large-latest"
                                    when /grok|xai/ then "grok-2"
                                    when /perplexity/ then "sonar"
                                    when /deepseek/ then "deepseek-chat"
                                    else "gpt-4.1" # Default fallback
                                    end
                    "ENV['#{provider_env_var}'] || #{default_model.inspect}"
                  else
                    # Fallback to default if no model and no environment variable
                    # This shouldn't typically happen due to initialization in app method
                    "\"gpt-4.1\""
                  end

    # Construct disabled logic based on API key availability and server mode restrictions
    if jupyter_disabled_in_server
      disabled_condition = "!defined?(CONFIG) || !CONFIG[\"#{provider_config.api_key_name}\"] || (defined?(CONFIG) && CONFIG[\"DISTRIBUTED_MODE\"] == \"server\")"
    else
      disabled_condition = "!defined?(CONFIG) || !CONFIG[\"#{provider_config.api_key_name}\"]"
    end

    # Add extra modules if specified
    include_modules = state.settings[:include_modules] || []
    include_statements = [helper_module]
    include_statements += include_modules
    include_lines = include_statements.map { |m| "        include #{m} if defined?(#{m})" }.join("\n")
    
    # Use group from features if defined, otherwise use provider's display_group
    group_value = state.features[:group] || provider_config.display_group
    
    class_def = <<~RUBY
      class #{state.name} < MonadicApp
#{include_lines}

        icon = #{state.ui[:icon].inspect}
        description = #{state.ui[:description].inspect}
        initial_prompt = #{state.prompts[:initial].inspect}

        @settings = {
          group: #{group_value.inspect},
          disabled: #{disabled_condition},
          models: #{model_list_code},
          model: #{model_value},
          temperature: #{state.settings[:temperature]},
          initial_prompt: initial_prompt,
          app_name: #{app_name.inspect},
          display_name: #{display_name.inspect},
          description: description,
          icon: icon,
        }
    RUBY

    # Add feature settings (excluding group which was already set)
    state.features.each do |feature, value|
      next if feature == :group  # Skip group as it's already set above
      class_def << "        @settings[:#{feature}] = #{value.inspect}\n"
    end
    
    # Add max_tokens if specified
    if state.settings[:max_tokens]
      class_def << "        @settings[:max_tokens] = #{state.settings[:max_tokens].inspect}\n"
    end
    
    # Add reasoning_effort if specified
    if state.settings[:reasoning_effort]
      class_def << "        @settings[:reasoning_effort] = #{state.settings[:reasoning_effort].inspect}\n"
    end
    
    # Add tools if specified
    if state.settings[:tools]
      class_def << "        @settings[:tools] = #{state.settings[:tools].inspect}\n"
    end
    
    class_def << "      end\n"
    
    eval(class_def, TOPLEVEL_BINDING, state.name)
  end

  # Utility method for state conversion to YAML
  def self.to_yaml(app_state)
    {
      name: app_state.name,
      settings: app_state.settings,
      features: app_state.features,
      ui: app_state.ui,
      prompts: app_state.prompts
    }.to_yaml
  end
end
