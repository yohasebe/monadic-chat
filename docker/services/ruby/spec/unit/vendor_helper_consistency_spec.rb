# frozen_string_literal: true

require_relative '../spec_helper'

RSpec.describe "Vendor Helper Consistency" do
  let(:vendor_helpers) do
    %w[
      openai claude gemini mistral cohere
      deepseek grok ollama
    ].map { |vendor| "#{vendor}_helper" }
  end
  
  let(:vendor_modules) do
    vendor_helpers.map do |helper|
      helper_path = File.join(
        File.dirname(__FILE__), 
        '../../lib/monadic/adapters/vendors/', 
        "#{helper}.rb"
      )
      
      if File.exist?(helper_path)
        require_relative helper_path
        # Special cases for modules with non-standard capitalization
        module_name = case helper
        when 'openai_helper'
          'OpenAIHelper'
        when 'deepseek_helper'
          'DeepSeekHelper'
        else
          helper.split('_').map(&:capitalize).join
        end
        Object.const_get(module_name)
      end
    end.compact
  end

  describe "Tool argument parsing" do
    # This used to call `parse_tool_arguments`, which no method in any helper
    # answers to — the guard skipped every module and the example asserted
    # nothing while passing. Best-of-Breed means the parsers are not named
    # alike (OpenAI has parse_function_call_arguments, Gemini
    # prepare_gemini_tool_arguments, Cohere inlines JSON.parse), so the
    # contract is checked against the entry point that exists rather than by
    # requiring a shared name.
    it "OpenAI's parser turns blank arguments into an empty hash" do
      helper = Class.new { include OpenAIHelper }.new

      expect(helper).to respond_to(:parse_function_call_arguments),
                        "the parser has been renamed; update this example to the new entry point"

      ["", "   ", nil].each do |blank|
        expect(helper.parse_function_call_arguments(blank)).to eq({}),
                                                               "blank arguments (#{blank.inspect}) should parse to {}"
      end
    end

    it "OpenAI's parser still reads well-formed arguments" do
      # Positive control: without this, a parser that returned {} for
      # everything would satisfy the example above.
      helper = Class.new { include OpenAIHelper }.new

      expect(helper.parse_function_call_arguments('{"city":"Kyoto"}')).to eq("city" => "Kyoto")
    end
  end

  describe "Array field validation" do
    it "all vendor helpers validate images field is an array" do
      vendor_helpers.each do |helper|
        helper_file = File.join(
          File.dirname(__FILE__), 
          '../../lib/monadic/adapters/vendors/', 
          "#{helper}.rb"
        )
        
        next unless File.exist?(helper_file)
        
        content = File.read(helper_file)
        
        # Check for proper array validation on images field
        images_assignments = content.scan(/res\["content"\]\["images"\]\s*=\s*obj\["images"\](.*)/)
        
        images_assignments.each do |assignment|
          condition = assignment[0]
          # Should have array check in the condition
          expect(condition).to match(/is_a\?\(Array\)|\.is_a\?\(Array\)/),
            "#{helper} should validate images is an array before assignment"
        end
      end
    end
  end
  
  describe "Role-based tool inclusion" do
    it "all vendor helpers skip tools when role is 'tool'" do
      vendor_helpers.each do |helper|
        helper_file = File.join(
          File.dirname(__FILE__), 
          '../../lib/monadic/adapters/vendors/', 
          "#{helper}.rb"
        )
        
        next unless File.exist?(helper_file)
        
        content = File.read(helper_file)
        
        # Check for role == "tool" conditions
        if content.include?("tools") && content.include?("role")
          # Should have logic to skip tools when role == "tool"
          expect(content).to match(/role\s*==\s*["']tool["']|role\s*!=\s*["']tool["']/),
            "#{helper} should have logic to handle role == 'tool'"
        end
      end
    end
  end
  
  describe "Model switching consistency" do
    it "all vendor helpers use consistent model switching patterns" do
      vendor_helpers.each do |helper|
        helper_file = File.join(
          File.dirname(__FILE__), 
          '../../lib/monadic/adapters/vendors/', 
          "#{helper}.rb"
        )
        
        next unless File.exist?(helper_file)
        
        content = File.read(helper_file)
        
        # Check for model switching patterns
        if content.include?("switch_model") || content.include?("image_model")
          # Should notify user when switching models
          expect(content).to match(/system_info|notify.*model|model.*switch/i),
            "#{helper} should notify user when switching models"
        end
      end
    end
  end
  
  describe "Error handling consistency" do
    it "all vendor helpers have consistent error handling" do
      vendor_helpers.each do |helper|
        helper_file = File.join(
          File.dirname(__FILE__), 
          '../../lib/monadic/adapters/vendors/', 
          "#{helper}.rb"
        )
        
        next unless File.exist?(helper_file)
        
        content = File.read(helper_file)
        
        # Check for api_request method
        if content.include?("def api_request")
          # Should have error handling
          expect(content).to match(/rescue|begin.*rescue|StandardError|HTTP::Error/),
            "#{helper} should have error handling in api_request"
        end
      end
    end
  end
end