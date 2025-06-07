# frozen_string_literal: true

require 'parser/current'

module MonadicDSL
  # Auto-completion system for MDSL tool definitions
  # Analyzes Ruby implementation files and generates corresponding MDSL tool definitions
  class ToolAutoCompleter
    attr_reader :standard_tools
    
    def initialize(app_directory_or_file = nil)
      @app_directory = app_directory_or_file
      @parser = Parser::CurrentRuby.new
      @standard_tools = discover_standard_tools
    end
    
    # Analyze a single MDSL file and its corresponding Ruby implementations
    def analyze_single_file(mdsl_file)
      return {} unless File.exist?(mdsl_file)
      
      app_dir = File.dirname(mdsl_file)
      ruby_files = Dir.glob(File.join(app_dir, "*_tools.rb"))
      
      analysis = {
        mdsl_file: mdsl_file,
        ruby_files: ruby_files,
        explicit_tools: extract_tools_from_mdsl(mdsl_file),
        implemented_tools: [],
        missing_definitions: [],
        orphaned_definitions: []
      }
      
      # Extract tools from Ruby implementation files
      ruby_files.each do |ruby_file|
        tools = extract_tool_methods_from_ruby(ruby_file)
        analysis[:implemented_tools].concat(tools)
      end
      
      analysis[:implemented_tools].uniq!
      
      # Find missing definitions (implemented but not defined in MDSL)
      analysis[:missing_definitions] = analysis[:implemented_tools] - analysis[:explicit_tools]
      
      # Find orphaned definitions (defined in MDSL but not implemented)
      analysis[:orphaned_definitions] = analysis[:explicit_tools] - analysis[:implemented_tools]
      
      analysis
    end
    
    # Analyze all MDSL files in a directory
    def analyze_directory(directory)
      return [] unless File.directory?(directory)
      
      mdsl_files = Dir.glob(File.join(directory, "**/*.mdsl"))
      analyses = []
      
      mdsl_files.each do |mdsl_file|
        analysis = analyze_single_file(mdsl_file)
        analyses << analysis if analysis.any?
      end
      
      analyses
    end
    
    # Generate auto-completion suggestions for missing tool definitions
    def generate_tool_definitions(missing_tools, ruby_files)
      definitions = []
      
      missing_tools.each do |tool_name|
        # Find the Ruby file that implements this tool
        ruby_file = find_implementation_file(tool_name, ruby_files)
        next unless ruby_file
        
        # Extract method signature and generate definition
        definition = generate_single_tool_definition(tool_name, ruby_file)
        definitions << definition if definition
      end
      
      definitions
    end
    
    # Generate a preview of what would be auto-completed
    def preview_auto_completion(mdsl_file)
      analysis = analyze_single_file(mdsl_file)
      return analysis if analysis[:missing_definitions].empty?
      
      analysis[:auto_completion_preview] = generate_tool_definitions(
        analysis[:missing_definitions], 
        analysis[:ruby_files]
      )
      
      analysis
    end
    
    private
    
    def discover_standard_tools
      # Static list of known standard tools
      known_standard = %w[
        fetch_text_from_office fetch_text_from_pdf fetch_text_from_file
        analyze_image analyze_audio analyze_video
        run_code run_script run_bash_command lib_installer check_environment
        fetch_web_content search_wikipedia
        write_to_file run_jupyter create_jupyter_notebook add_jupyter_cells system_info
      ]
      
      # Dynamically discover additional standard tools from MonadicApp if available
      begin
        if defined?(MonadicApp)
          instance_methods = MonadicApp.instance_methods(false)
          standard_tool_pattern = /^(fetch_|analyze_|run_|lib_|check_|search_|write_|create_|add_|system_)/
          dynamic_standard = instance_methods.select { |m| m.to_s.match?(standard_tool_pattern) }.map(&:to_s)
          known_standard = (known_standard + dynamic_standard).uniq
        end
      rescue
        # Fallback to static list if dynamic discovery fails
      end
      
      known_standard
    end
    
    def extract_tool_methods_from_ruby(ruby_file)
      return [] unless File.exist?(ruby_file)
      
      content = File.read(ruby_file)
      
      # Find the private keyword position to separate public from private methods
      private_keyword_pos = content.index(/^\s*private\s*$/)
      
      # If there's a private section, only consider methods before it
      if private_keyword_pos
        public_content = content[0...private_keyword_pos]
      else
        public_content = content
      end
      
      # Extract method definitions that could be tools from public section only
      methods = public_content.scan(/def\s+(\w+)/).flatten
      
      # Filter out obvious non-tool methods
      excluded_patterns = /^(initialize|private|protected|validate|format|parse|setup|teardown|before|after|test_|spec_)/
      potential_tools = methods.reject { |method| 
        method.match?(excluded_patterns) || @standard_tools.include?(method)
      }
      
      potential_tools
    end
    
    def extract_tools_from_mdsl(mdsl_file)
      return [] unless File.exist?(mdsl_file)
      
      content = File.read(mdsl_file)
      content.scan(/define_tool\s+"([^"]+)"/).flatten
    end
    
    def find_implementation_file(tool_name, ruby_files)
      ruby_files.find do |ruby_file|
        content = File.read(ruby_file)
        content.include?("def #{tool_name}")
      end
    end
    
    def generate_single_tool_definition(tool_name, ruby_file)
      content = File.read(ruby_file)
      
      # Find the method definition
      method_match = content.match(/def\s+#{Regexp.escape(tool_name)}\s*(\([^)]*\))?/)
      return nil unless method_match
      
      # Extract parameter information
      parameters = extract_method_parameters(method_match[1])
      
      # Generate description based on method name
      description = generate_method_description(tool_name)
      
      {
        name: tool_name,
        description: description,
        parameters: parameters
      }
    end
    
    def extract_method_parameters(params_string)
      return [] unless params_string
      
      # Remove parentheses if present
      params_string = params_string.gsub(/[()]/, '')
      
      # Parse parameter definitions
      parameters = []
      param_parts = params_string.split(',').map(&:strip)
      
      param_parts.each do |param_part|
        next if param_part.empty?
        
        # Handle keyword arguments with defaults
        if param_part.include?(':')
          param_info = parse_keyword_parameter(param_part)
          parameters << param_info if param_info
        end
      end
      
      parameters
    end
    
    def parse_keyword_parameter(param_part)
      # Parse keyword parameter like "filename: 'default.txt'" or "required_param:"
      if param_part.match(/(\w+):\s*(.*)/)
        param_name = $1
        default_value = $2.strip
        
        # Infer type from default value
        type = infer_type_from_default_value(default_value)
        required = default_value.empty?
        
        {
          name: param_name,
          type: type,
          required: required,
          description: generate_parameter_description(param_name, type)
        }
      end
    end
    
    def infer_type_from_default_value(default_value)
      case default_value
      when /^["'].*["']$/ then "string"
      when /^\d+$/ then "integer"
      when /^\d+\.\d+$/ then "number"
      when /^(true|false)$/ then "boolean"
      when /^\[.*\]$/ then "array"
      when /^\{.*\}$/ then "object"
      when "" then "string" # Empty default usually means string
      else "string" # Default fallback
      end
    end
    
    def generate_method_description(method_name)
      # Convert snake_case to human readable description
      words = method_name.split('_')
      
      # Handle common patterns
      if words.first == "count"
        "Count the #{words[1..-1].join(' ')}"
      elsif words.first == "create"
        "Create #{words[1..-1].join(' ')}"
      elsif words.first == "write"
        "Write #{words[1..-1].join(' ')}"
      elsif words.first == "read"
        "Read #{words[1..-1].join(' ')}"
      elsif words.first == "validate"
        "Validate #{words[1..-1].join(' ')}"
      elsif words.first == "check"
        "Check #{words[1..-1].join(' ')}"
      else
        # Generic conversion
        words.map(&:capitalize).join(' ')
      end
    end
    
    def generate_parameter_description(param_name, type)
      # Generate description based on parameter name and type
      case param_name
      when /text|content|message/
        "The text content to process"
      when /file|filename/
        "The file name or path"
      when /path/
        "The file path"
      when /data/
        "The data to process"
      when /config|configuration/
        "Configuration settings"
      when /options|opts/
        "Additional options"
      else
        "The #{param_name.gsub('_', ' ')}"
      end
    end
  end
end