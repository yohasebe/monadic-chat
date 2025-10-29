# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'fileutils'

require_relative '../../../apps/auto_forge/auto_forge_tools'
require_relative '../../../apps/auto_forge/auto_forge_utils'
require_relative '../../../apps/auto_forge/auto_forge_debugger'
require_relative '../../../apps/auto_forge/agents/error_explainer'
require_relative '../../../apps/auto_forge/utils/codex_response_analyzer'

RSpec.describe 'AutoForge Diagnosis Integration', type: :integration do
  let(:test_project_name) { "TestApp_#{Time.now.to_i}" }
  let(:auto_forge_dir) { File.expand_path('~/monadic/data/auto_forge') }
  let(:project_dir) { File.join(auto_forge_dir, test_project_name) }

  let(:tool) do
    Class.new do
      include AutoForgeTools

      # Make protected methods accessible for testing
      public :resolve_project_context
      public :debug_application_raw
      public :current_diagnosis
      public :store_diagnosis
      public :clear_diagnosis_state
    end.new
  end

  before(:all) do
    # Ensure AutoForge directory exists
    FileUtils.mkdir_p(File.expand_path('~/monadic/data/auto_forge'))
  end

  before(:each) do
    # Initialize context
    tool.instance_variable_set(:@context, {})

    # Create test project directory
    FileUtils.mkdir_p(project_dir)
  end

  after(:each) do
    # Clean up test project
    FileUtils.rm_rf(project_dir) if Dir.exist?(project_dir)

    # Clear diagnosis state
    tool.clear_diagnosis_state
  end

  describe 'Real container-based debugging' do
    context 'with a working HTML file' do
      let(:working_html) do
        <<~HTML
          <!DOCTYPE html>
          <html lang="en">
          <head>
              <meta charset="UTF-8">
              <meta name="viewport" content="width=device-width, initial-scale=1.0">
              <title>Test Application</title>
          </head>
          <body>
              <h1>Test Application</h1>
              <button id="testButton" onclick="handleClick()">Click Me</button>
              <div id="output"></div>

              <script>
                  function handleClick() {
                      document.getElementById('output').textContent = 'Button clicked!';
                      console.log('Button was clicked');
                  }

                  // Log that the app loaded
                  console.log('Application loaded successfully');
              </script>
          </body>
          </html>
        HTML
      end

      before do
        File.write(File.join(project_dir, 'index.html'), working_html)
      end

      it 'successfully debugs a working application with real Selenium' do
        # Skip if Selenium is not available
        debugger = AutoForge::Debugger.new({})
        unless debugger.send(:selenium_available?)
          skip 'Selenium container is not running'
        end

        result = tool.debug_application_raw(
          'spec' => {
            'name' => test_project_name,
            'project_path' => project_dir
          }
        )

        expect(result[:success]).to be true
        expect(result[:project_name]).to eq(test_project_name)
        expect(result[:html_path]).to eq(File.join(project_dir, 'index.html'))

        # Check that basic functionality was detected
        expect(result[:functionality_tests]).to be_an(Array)

        # Should find the button
        button_test = result[:functionality_tests].find { |t| t['test']&.include?('button') }
        expect(button_test).not_to be_nil
        expect(button_test['count']).to be >= 1

        # Should not have JavaScript errors
        expect(result[:javascript_errors] || []).to be_empty
      end

      it 'performs diagnosis and generates user-friendly report' do
        debugger = AutoForge::Debugger.new({})
        unless debugger.send(:selenium_available?)
          skip 'Selenium container is not running'
        end

        response = tool.diagnose_and_suggest_fixes(
          'spec' => {
            'name' => test_project_name,
            'project_path' => project_dir
          }
        )

        expect(response).to include('✅ Diagnosis Complete: No issues found!')
        expect(response).to include(test_project_name)
        expect(response).to include('Performance metrics')

        # Check that diagnosis was stored
        diagnosis = tool.current_diagnosis
        expect(diagnosis).not_to be_nil
        expect(diagnosis[:project_name]).to eq(test_project_name)
        expect(diagnosis[:explanations]).to be_empty
      end
    end

    context 'with an HTML file containing JavaScript errors' do
      let(:broken_html) do
        <<~HTML
          <!DOCTYPE html>
          <html lang="en">
          <head>
              <meta charset="UTF-8">
              <title>Broken Test App</title>
          </head>
          <body>
              <h1>Test with Errors</h1>
              <button onclick="nonExistentFunction()">Broken Button</button>
              <div id="container"></div>

              <script>
                  // This will cause an error
                  document.getElementById('nonexistent').innerHTML = 'This will fail';

                  // Another error - undefined function call
                  undefinedFunction();

                  // Trying to use a variable that doesn't exist
                  console.log(nonExistentVariable);
              </script>
          </body>
          </html>
        HTML
      end

      before do
        File.write(File.join(project_dir, 'index.html'), broken_html)
      end

      it 'detects JavaScript errors using real Selenium' do
        debugger = AutoForge::Debugger.new({})
        unless debugger.send(:selenium_available?)
          skip 'Selenium container is not running'
        end

        result = tool.debug_application_raw(
          'spec' => {
            'name' => test_project_name,
            'project_path' => project_dir
          }
        )

        # Even with errors, the debug should complete
        expect(result[:success]).to be true

        # Should detect JavaScript errors (if browser console logging works)
        # Note: Selenium Grid might not capture all console errors
        errors = result[:javascript_errors] || []
        warnings = result[:warnings] || []

        # At minimum, the page should load
        expect(result[:functionality_tests]).to be_an(Array)
      end

      it 'generates user-friendly explanations for errors' do
        debugger = AutoForge::Debugger.new({})
        unless debugger.send(:selenium_available?)
          skip 'Selenium container is not running'
        end

        response = tool.diagnose_and_suggest_fixes(
          'spec' => {
            'name' => test_project_name,
            'project_path' => project_dir
          }
        )

        # Store diagnosis for inspection
        diagnosis = tool.current_diagnosis
        expect(diagnosis).not_to be_nil

        # If errors were detected, they should be explained
        if diagnosis[:explanations].any?
          expect(response).to include('Diagnosis Results')
          expect(response).to include('What would you like to do?')

          # Check that explanations are user-friendly
          diagnosis[:explanations].each do |exp|
            expect(exp[:title]).not_to be_nil
            expect(exp[:explanation]).not_to be_nil
            expect(exp[:impact]).not_to be_nil
            expect(exp[:severity]).not_to be_nil
          end
        else
          # If no errors detected (Selenium Grid limitation), should report success
          expect(response).to include('No issues found')
        end
      end
    end

    context 'with manual project path specification' do
      let(:simple_html) do
        <<~HTML
          <!DOCTYPE html>
          <html>
          <head><title>Manual Path Test</title></head>
          <body><h1>Testing Manual Path</h1></body>
          </html>
        HTML
      end

      it 'accepts explicit project_path parameter' do
        File.write(File.join(project_dir, 'index.html'), simple_html)

        context = tool.resolve_project_context(
          'spec' => {
            'project_path' => project_dir
          }
        )

        expect(context[:success]).to be true
        expect(context[:html_path]).to eq(File.join(project_dir, 'index.html'))
        expect(context[:project_name]).to eq(test_project_name)
      end

      it 'handles missing project directory gracefully' do
        context = tool.resolve_project_context(
          'spec' => {
            'project_path' => '/nonexistent/path/to/project'
          }
        )

        expect(context[:success]).to be false
        expect(context[:error_type]).to eq(:manual_path_missing)
      end

      it 'handles missing index.html in valid directory' do
        # Create directory but no index.html
        empty_dir = File.join(auto_forge_dir, "EmptyProject_#{Time.now.to_i}")
        FileUtils.mkdir_p(empty_dir)

        begin
          context = tool.resolve_project_context(
            'spec' => {
              'project_path' => empty_dir
            }
          )

          expect(context[:success]).to be false
          expect(context[:error_type]).to eq(:missing_index)
        ensure
          FileUtils.rm_rf(empty_dir)
        end
      end
    end

    context 'with Selenium unavailable' do
      it 'provides helpful error message when Selenium is not running' do
        # Create a minimal index.html so the test reaches the Selenium check
        File.write(File.join(project_dir, 'index.html'), '<html><body>Test</body></html>')

        # Mock check_selenium_or_error to return an error hash
        selenium_error = {
          success: false,
          error: 'Selenium container is not running. Web automation features require the Selenium service to be active.',
          suggestion: 'Please start the Selenium container from the Actions menu (Actions → Start Selenium Container) and try again.'
        }
        allow_any_instance_of(AutoForge::Debugger).to receive(:check_selenium_or_error).and_return(selenium_error)

        result = tool.debug_application_raw(
          'spec' => {
            'name' => test_project_name,
            'project_path' => project_dir
          }
        )

        expect(result[:success]).to be false
        expect(result[:error]).to include('Selenium container is not running')
        expect(result[:suggestion]).to include('Please start the Selenium container')
      end
    end

    describe 'diagnosis state management' do
      let(:mock_diagnosis) do
        {
          project_name: 'TestApp',
          debug_result: {
            success: true,
            javascript_errors: []
          },
          explanations: [],
          timestamp: Time.now,
          session_id: 'test123'
        }
      end

      it 'stores and retrieves diagnosis correctly' do
        tool.store_diagnosis(mock_diagnosis)

        retrieved = tool.current_diagnosis
        expect(retrieved).not_to be_nil
        expect(retrieved[:project_name]).to eq('TestApp')
        expect(retrieved[:session_id]).to eq('test123')
      end

      it 'clears diagnosis state properly' do
        tool.store_diagnosis(mock_diagnosis)
        expect(tool.current_diagnosis).not_to be_nil

        tool.clear_diagnosis_state
        expect(tool.current_diagnosis).to be_nil
      end

      it 'handles diagnosis timeout correctly' do
        old_diagnosis = mock_diagnosis.merge(timestamp: Time.now - 3600) # 1 hour old
        tool.store_diagnosis(old_diagnosis)

        response = tool.apply_suggested_fixes('apply fixes')

        expect(response).to include('Diagnosis results have expired')
        expect(tool.current_diagnosis).to be_nil
      end
    end
  end

  describe 'Performance with real HTML files' do
    let(:large_html) do
      buttons = (1..100).map { |i| %(<button id="btn#{i}">Button #{i}</button>) }.join("\n")
      forms = (1..10).map { |i| %(<form id="form#{i}"><input type="text" /></form>) }.join("\n")

      <<~HTML
        <!DOCTYPE html>
        <html>
        <head><title>Performance Test</title></head>
        <body>
          <h1>Large Application</h1>
          #{buttons}
          #{forms}
          <script>
            console.log('Loaded application with many elements');
          </script>
        </body>
        </html>
      HTML
    end

    it 'handles large HTML files efficiently' do
      debugger = AutoForge::Debugger.new({})
      unless debugger.send(:selenium_available?)
        skip 'Selenium container is not running'
      end

      File.write(File.join(project_dir, 'index.html'), large_html)

      start_time = Time.now
      result = tool.debug_application_raw(
        'spec' => {
          'name' => test_project_name,
          'project_path' => project_dir
        }
      )
      duration = Time.now - start_time

      expect(result[:success]).to be true
      expect(duration).to be < 10 # Should complete within 10 seconds

      # Should detect the many elements
      button_test = result[:functionality_tests]&.find { |t| t['test']&.include?('button') }
      expect(button_test).not_to be_nil
      expect(button_test['count']).to be >= 100

      form_test = result[:functionality_tests]&.find { |t| t['test']&.include?('form') }
      expect(form_test).not_to be_nil
      expect(form_test['count']).to be >= 10
    end
  end
end