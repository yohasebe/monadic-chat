require 'spec_helper'

RSpec.describe "DSL tools block parsing" do
  describe "regex pattern for matching tools block" do
    # The new regex pattern that properly handles nested blocks
    let(:tools_regex) { /(.*?^(\s*)tools\s+do\s*\n)(.*?)(^\2end.*)/m }
    
    context "with empty tools block" do
      let(:content) do
        <<~MDSL
          app "TestApp" do
            tools do
            end
          end
        MDSL
      end
      
      it "correctly matches the tools block" do
        match = content.match(tools_regex)
        expect(match).not_to be_nil
        expect(match[1]).to include('app "TestApp"')
        expect(match[3].strip).to eq("")  # Empty tools content
        expect(match[4]).to start_with("  end")  # The closing end for tools
      end
    end
    
    context "with tools containing nested end statements" do
      let(:content) do
        <<~MDSL
          app "TestApp" do
            tools do
              define_tool "test", "description" do
                parameter :param, "string", "desc"
              end
            end
          end
        MDSL
      end
      
      it "correctly matches the entire tools block" do
        match = content.match(tools_regex)
        expect(match).not_to be_nil
        expect(match[3]).to include('define_tool')
        expect(match[3]).to include('parameter')
        expect(match[3]).to include('end')  # The end for define_tool
        expect(match[4].strip).to start_with('end')  # The end for tools block
      end
    end
    
    context "with multiple nested tools" do
      let(:content) do
        <<~MDSL
          app "TestApp" do
            llm do
              provider "openai"
            end
            
            tools do
              define_tool "tool1", "desc1" do
                parameter :p1, "string", "param1"
              end
              
              define_tool "tool2", "desc2" do
                parameter :p2, "integer", "param2"
              end
            end
          end
        MDSL
      end
      
      it "captures all tools in the content section" do
        match = content.match(tools_regex)
        expect(match).not_to be_nil
        expect(match[3]).to include('define_tool "tool1"')
        expect(match[3]).to include('define_tool "tool2"')
        expect(match[3].scan(/\bend\b/).count).to eq(2)  # Two ends for the tools
      end
    end
    
    context "edge case: string containing do/end keywords" do
      let(:content) do
        <<~MDSL
          app "TestApp" do
            description "This app helps you do things and end tasks"
            
            tools do
              define_tool "helper", "Helps to do and end things" do
                parameter :action, "string", "What to do"
              end
            end
          end
        MDSL
      end
      
      it "doesn't get confused by do/end in strings" do
        match = content.match(tools_regex)
        expect(match).not_to be_nil
        expect(match[3]).to include('define_tool "helper"')
        expect(match[3]).not_to include('This app helps')  # Should not capture the description
      end
    end
  end
  
  describe "fallback parsing method" do
    def parse_tools_block_with_fallback(content)
      # First try the regex
      tools_regex = /(.*?^(\s*)tools\s+do\s*\n)(.*?)(^\2end.*)/m
      tools_block_match = content.match(tools_regex)
      
      if tools_block_match
        {
          before: tools_block_match[1],
          content: tools_block_match[3],
          after: tools_block_match[4]
        }
      else
        # Fallback parsing logic from the DSL module
        tools_start_index = content.index(/^\s*tools\s+do\s*$/m)
        return nil unless tools_start_index
        
        indent_match = content[tools_start_index..].match(/^(\s*)tools/)
        indent = indent_match[1]
        
        after_tools_do = content[(tools_start_index + content[tools_start_index..].index("\n") + 1)..]
        
        lines = after_tools_do.lines
        nesting_level = 1
        tools_content_lines = []
        remaining_lines = []
        found_end = false
        
        lines.each_with_index do |line, idx|
          if !found_end
            if line.match(/\bdo\s*$/)
              nesting_level += 1
            elsif line.match(/^#{Regexp.escape(indent)}end\b/) && nesting_level == 1
              found_end = true
              remaining_lines = lines[idx..]
            elsif line.match(/\bend\b/)
              nesting_level -= 1
            end
            
            tools_content_lines << line unless found_end
          end
        end
        
        return nil unless found_end
        
        {
          before: content[0...tools_start_index] + indent + "tools do\n",
          content: tools_content_lines.join,
          after: remaining_lines.join
        }
      end
    end
    
    context "with complex indentation" do
      let(:content) do
        <<~MDSL
            app "TestApp" do
              features do
                easy_submit true
              end
              
              tools do
                define_tool "complex", "Complex tool" do
                  parameter :data, "object", "Complex data" do
                    # Comment
                  end
                end
              end
              
              system_prompt "Test"
            end
        MDSL
      end
      
      it "correctly parses using fallback method" do
        result = parse_tools_block_with_fallback(content)
        expect(result).not_to be_nil
        expect(result[:content]).to include('define_tool "complex"')
        expect(result[:after]).to include('system_prompt')
      end
    end
  end
end