# frozen_string_literal: true

require_relative '../spec_helper'

RSpec.describe "Code Interpreter System Tests", type: :system do
  before(:all) do
    skip "System tests require full Docker environment" unless system_tests_available?
  end

  # Test that all Code Interpreter apps can be loaded and have correct tool definitions
  describe "Code Interpreter App Loading" do
    let(:app_base_dir) do
      if Dir.pwd.end_with?('docker/services/ruby')
        File.join(Dir.pwd, "apps")
      else
        File.join(Dir.pwd, "docker", "services", "ruby", "apps")
      end
    end

    let(:code_interpreter_files) do
      Dir.glob(File.join(app_base_dir, "code_interpreter", "*.mdsl"))
    end

    it "loads all Code Interpreter MDSL files without errors" do
      expect(code_interpreter_files).not_to be_empty
      
      code_interpreter_files.each do |file|
        expect(File.exist?(file)).to be true
        content = File.read(file)
        
        # Basic validation that it's a proper MDSL file
        expect(content).to include('app "')
        expect(content).to include('tools do')
        expect(content).to include('end')
      end
    end

    it "has correct parameter names for fetch tools in all Code Interpreters" do
      code_interpreter_files.each do |file|
        content = File.read(file)
        
        # Check fetch_text_from_file parameter
        if content.include?('fetch_text_from_file')
          expect(content).to include('parameter :file,')
          expect(content).not_to include('parameter :file_path,')
        end
        
        # Check fetch_text_from_pdf parameter  
        if content.include?('fetch_text_from_pdf')
          expect(content).to include('parameter :pdf,')
          expect(content).not_to include('parameter :pdf_path,')
        end
        
        # Check fetch_text_from_office parameter
        if content.include?('fetch_text_from_office')
          expect(content).to include('parameter :file,')
          expect(content).not_to include('parameter :office_path,')
        end
      end
    end

    it "has proper execution emphasis in system prompts" do
      emphasis_required = %w[
        code_interpreter_mistral.mdsl
        code_interpreter_cohere.mdsl 
        code_interpreter_grok.mdsl
        code_interpreter_deepseek.mdsl
      ]
      
      emphasis_required.each do |filename|
        file_path = code_interpreter_files.find { |f| f.end_with?(filename) }
        next unless file_path
        
        content = File.read(file_path)
        # Check for various execution emphasis patterns
        expect(content.downcase).to include('must execute').or include('must').and include('execute')
      end
    end

    it "has correct API key requirements" do
      api_key_mapping = {
        'code_interpreter_openai.mdsl' => 'OPENAI_API_KEY',
        'code_interpreter_claude.mdsl' => 'ANTHROPIC_API_KEY', 
        'code_interpreter_gemini.mdsl' => 'GEMINI_API_KEY',
        'code_interpreter_mistral.mdsl' => 'MISTRAL_API_KEY',
        'code_interpreter_cohere.mdsl' => 'COHERE_API_KEY',
        'code_interpreter_grok.mdsl' => 'XAI_API_KEY',
        'code_interpreter_deepseek.mdsl' => 'DEEPSEEK_API_KEY'
      }
      
      api_key_mapping.each do |filename, expected_key|
        file_path = code_interpreter_files.find { |f| f.end_with?(filename) }
        next unless file_path
        
        content = File.read(file_path)
        expect(content).to include(expected_key)
      end
    end
  end

  describe "Tool Parameter Consistency" do
    let(:all_apps_with_fetch_tools) do
      # Find all apps that use fetch_text_from_* tools
      base_dir = if Dir.pwd.end_with?('docker/services/ruby')
                   File.join(Dir.pwd, "apps")
                 else
                   File.join(Dir.pwd, "docker", "services", "ruby", "apps")
                 end
      
      all_mdsl_files = Dir.glob(File.join(base_dir, "**", "*.mdsl"))
      all_mdsl_files.select do |file|
        content = File.read(file)
        content.include?('fetch_text_from_file') || 
        content.include?('fetch_text_from_pdf') || 
        content.include?('fetch_text_from_office')
      end
    end

    it "uses consistent parameter names across all apps with fetch tools" do
      all_apps_with_fetch_tools.each do |file|
        content = File.read(file)
        app_name = File.basename(file, '.mdsl')
        
        # No longer need to skip apps since auto-completion comments have been removed
        # and proper tool definitions have been added
        
        # Check fetch_text_from_file parameter consistency (only if tool is explicitly defined)
        if content.include?('define_tool "fetch_text_from_file"')
          expect(content).to include('parameter :file,'), 
            "#{app_name} should use 'parameter :file,' for fetch_text_from_file"
        end
        
        # Check fetch_text_from_pdf parameter consistency (only if tool is explicitly defined)
        if content.include?('define_tool "fetch_text_from_pdf"')
          expect(content).to include('parameter :pdf,'),
            "#{app_name} should use 'parameter :pdf,' for fetch_text_from_pdf"
        end
        
        # Check fetch_text_from_office parameter consistency (only if tool is explicitly defined)
        if content.include?('define_tool "fetch_text_from_office"')
          expect(content).to include('parameter :file,'),
            "#{app_name} should use 'parameter :file,' for fetch_text_from_office"
        end
      end
    end
  end

  private

  def system_tests_available?
    # Define app_base_dir within the method
    base_dir = if Dir.pwd.end_with?('docker/services/ruby')
                 File.join(Dir.pwd, "apps")
               else
                 File.join(Dir.pwd, "docker", "services", "ruby", "apps")
               end
    
    # Check if we have access to the apps directory
    return false unless Dir.exist?(base_dir)
    
    # Check if we have MDSL files
    mdsl_files = Dir.glob(File.join(base_dir, "**", "*.mdsl"))
    mdsl_files.any?
  end
end