# frozen_string_literal: true

require 'spec_helper'
require 'fileutils'
require_relative '../../../apps/auto_forge/auto_forge_tools'
require_relative '../../../apps/auto_forge/auto_forge_utils'

RSpec.describe 'AutoForge debugging (integration)', type: :integration do
  include AutoForgeTools

  before(:all) do
    begin
      @selenium_available = AutoForge::Debugger.new({}).send(:selenium_available?)
    rescue => e
      @selenium_available = false
      @selenium_error = e
    end

    @project_path = Dir.mktmpdir('autoforge_debug_integration')
    @project_name = File.basename(@project_path)

    File.write(
      File.join(@project_path, 'index.html'),
      <<~HTML
        <!DOCTYPE html>
        <html>
          <head>
            <meta charset="utf-8" />
            <title>Integration Debug Test</title>
            <script>
              window.addEventListener('DOMContentLoaded', () => {
                const heading = document.createElement('h1');
                heading.textContent = 'Integration Debug Test';
                document.body.appendChild(heading);
              });
            </script>
          </head>
          <body>
            <p id="status">ready</p>
          </body>
        </html>
      HTML
    )
  end

  after(:all) do
    FileUtils.rm_rf(@project_path) if @project_path && Dir.exist?(@project_path)
  end

  before do
    skip("Selenium container is not available: #{@selenium_error&.message || 'container not running'}") unless @selenium_available
    @context = {}
  end

  it 'runs debug_application_raw against Selenium container' do
    result = debug_application_raw('spec' => { 'name' => @project_name, 'project_path' => @project_path })

    expect(result[:success]).to be(true)
    expect(result[:project_name]).to eq(@project_name)
    expect(result[:javascript_errors]).to be_empty
    expect(result[:warnings]).to be_empty
  end

  it 'returns a friendly summary via debug_application' do
    output = debug_application('spec' => { 'name' => @project_name, 'project_path' => @project_path })

    expect(output).to include('🔍 Debug Report')
    expect(output).to include(@project_name)
    expect(output).to include('No JavaScript errors')
  end
end
