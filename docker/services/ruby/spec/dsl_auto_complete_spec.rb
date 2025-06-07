require 'spec_helper'
require_relative '../lib/monadic/dsl'
# Skip loading tool_auto_completer if parser gem is not available
begin
  require_relative '../lib/monadic/dsl/tool_auto_completer'
rescue LoadError
  # Parser gem not available, skip auto-completer tests
end

RSpec.describe MonadicDSL::ToolConfiguration do
  describe '#write_auto_completed_tools_to_mdsl' do
    let(:temp_dir) { Dir.mktmpdir }
    let(:mdsl_file) { File.join(temp_dir, 'test_app.mdsl') }
    
    after do
      FileUtils.rm_rf(temp_dir)
    end
    
    context 'when tools block is empty' do
      before do
        File.write(mdsl_file, <<~MDSL)
          app "TestApp" do
            llm do
              provider "openai"
            end
            
            tools do
            end
          end
        MDSL
      end
      
      it 'adds tools without duplicating end statements' do
        state = MonadicDSL::AppState.new("TestApp")
        state.settings[:provider] = "openai"
        
        tool_config = MonadicDSL::ToolConfiguration.new(state, :openai)
        
        # Simulate auto-completed tools
        auto_completed_tools = [
          {
            name: "test_tool",
            description: "Test tool description",
            parameters: [
              { name: "param1", type: "string", description: "Test parameter", required: true }
            ]
          }
        ]
        
        # Write auto-completed tools
        tool_config.send(:write_auto_completed_tools_to_mdsl, mdsl_file, auto_completed_tools)
        
        content = File.read(mdsl_file)
        
        # Count 'end' statements
        end_count = content.scan(/^\s*end\s*$/).count
        
        # Should have exactly 3 ends: one for tools, one for app, one for llm
        expect(end_count).to eq(3)
        
        # Verify the tool was added
        expect(content).to include('define_tool "test_tool"')
        expect(content).to include('parameter :param1')
      end
    end
    
    context 'when tools block has existing tools' do
      before do
        File.write(mdsl_file, <<~MDSL)
          app "TestApp" do
            llm do
              provider "openai"
            end
            
            tools do
              define_tool "existing_tool", "Existing tool" do
                parameter :existing_param, "string", "Existing parameter", required: true
              end
            end
          end
        MDSL
      end
      
      it 'appends new tools without duplicating end statements' do
        state = MonadicDSL::AppState.new("TestApp")
        state.settings[:provider] = "openai"
        
        tool_config = MonadicDSL::ToolConfiguration.new(state, :openai)
        
        # Simulate auto-completed tools
        auto_completed_tools = [
          {
            name: "new_tool",
            description: "New tool description",
            parameters: []
          }
        ]
        
        # Write auto-completed tools
        tool_config.send(:write_auto_completed_tools_to_mdsl, mdsl_file, auto_completed_tools)
        
        content = File.read(mdsl_file)
        
        # Count 'end' statements
        end_count = content.scan(/^\s*end\s*$/).count
        
        # Should have exactly 4 ends: one for existing tool, one for tools, one for app, one for llm
        expect(end_count).to eq(4)
        
        # Verify both tools are present
        expect(content).to include('define_tool "existing_tool"')
        expect(content).to include('define_tool "new_tool"')
        
        # Verify structure is correct
        expect(content).to match(/tools do.*define_tool "existing_tool".*end.*define_tool "new_tool".*end.*end/m)
      end
    end
    
    context 'with complex nested structures' do
      before do
        File.write(mdsl_file, <<~MDSL)
          app "ComplexApp" do
            description <<~TEXT
              This is a complex app with nested blocks
              do
                # This 'do' in the string shouldn't confuse the parser
              end
            TEXT
            
            llm do
              provider "openai"
              model "gpt-4" do
                # Nested block
              end
            end
            
            features do
              easy_submit do
                # Another nested block
              end
            end
            
            tools do
              define_tool "complex_tool", "Complex tool" do
                parameter :param1, "string", "Parameter 1" do
                  # Even parameters can have blocks
                end
              end
            end
          end
        MDSL
      end
      
      it 'correctly identifies tools block boundaries' do
        state = MonadicDSL::AppState.new("ComplexApp")
        state.settings[:provider] = "openai"
        
        tool_config = MonadicDSL::ToolConfiguration.new(state, :openai)
        
        # Simulate auto-completed tools
        auto_completed_tools = [
          {
            name: "auto_tool",
            description: "Auto-generated tool",
            parameters: []
          }
        ]
        
        # Write auto-completed tools
        tool_config.send(:write_auto_completed_tools_to_mdsl, mdsl_file, auto_completed_tools)
        
        content = File.read(mdsl_file)
        
        # Verify the file is still valid Ruby
        expect { eval(content) }.not_to raise_error
        
        # Verify tools were added in the right place
        expect(content).to include('define_tool "complex_tool"')
        expect(content).to include('define_tool "auto_tool"')
        
        # Make sure the heredoc wasn't corrupted
        expect(content).to include("This is a complex app with nested blocks")
      end
    end
  end
end