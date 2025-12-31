# frozen_string_literal: true

# Document Generator Integration Test
#
# Tests Document Generator (Claude Skills API) configuration and basic API connectivity.
#
# Full artifact generation testing requires the server to be running with WebSocket
# connections, as Skills API uses multi-turn streaming responses.
#
# Run with:
#   PROVIDERS=anthropic RUN_API=true bundle exec rspec spec/integration/document_generator_artifact_spec.rb

require_relative '../spec_helper'
require 'net/http'
require 'json'

RSpec.describe 'Document Generator Integration', :api, :artifacts do
  before(:each) do
    skip "RUN_API not enabled" unless ENV['RUN_API'] == 'true'
    skip "ANTHROPIC_API_KEY not set" unless ENV['ANTHROPIC_API_KEY'] && !ENV['ANTHROPIC_API_KEY'].empty?
    skip "DocumentGeneratorClaude app not available" unless defined?(APPS) && APPS['DocumentGeneratorClaude']
  end

  describe 'App Configuration' do
    it 'has correct Skills configuration' do
      app = APPS['DocumentGeneratorClaude']

      # Verify skills are configured
      skills = app.settings['skills']
      expect(skills).to be_an(Array)
      expect(skills).to include('xlsx', 'pptx', 'docx', 'pdf')

      # Verify betas are configured
      betas = app.settings['betas']
      expect(betas).to be_an(Array)
      expect(betas).to include('code-execution-2025-08-25')
      expect(betas).to include('skills-2025-10-02')
      expect(betas).to include('files-api-2025-04-14')
    end

    it 'has file operations tools imported' do
      app = APPS['DocumentGeneratorClaude']

      # Verify tools are configured
      tools = app.settings['tools']
      expect(tools).to be_an(Array)

      tool_names = tools.map { |t| t['name'] || t[:name] }
      expect(tool_names).to include('list_files_in_shared_folder')
    end
  end

  describe 'API Connectivity' do
    it 'accepts Skills API request format' do
      api_key = ENV['ANTHROPIC_API_KEY']
      app = APPS['DocumentGeneratorClaude']
      model = app.settings['model'] || 'claude-sonnet-4-5-20250929'

      uri = URI('https://api.anthropic.com/v1/messages')

      headers = {
        'Content-Type' => 'application/json',
        'x-api-key' => api_key,
        'anthropic-version' => '2023-06-01',
        'anthropic-beta' => 'code-execution-2025-08-25,skills-2025-10-02,files-api-2025-04-14'
      }

      # Simple test request
      body = {
        model: model,
        max_tokens: 100,
        system: 'You are a test assistant. Just say hello.',
        messages: [{ role: 'user', content: 'Say hello' }],
        tools: [{ type: 'code_execution_20250825', name: 'code_execution' }],
        container: {
          skills: [{ type: 'anthropic', skill_id: 'xlsx' }]
        }
      }

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.read_timeout = 60

      request = Net::HTTP::Post.new(uri)
      headers.each { |k, v| request[k] = v }
      request.body = JSON.generate(body)

      response = http.request(request)
      result = JSON.parse(response.body)

      # Verify API accepted the request (not a 4xx error for bad parameters)
      expect(response.code.to_i).to be < 500, "Server error: #{result}"

      if response.code.to_i >= 400
        # Check if it's a parameter error vs rate limit/quota
        error_type = result.dig('error', 'type')
        error_msg = result.dig('error', 'message') || ''

        acceptable_errors = ['rate_limit_error', 'overloaded_error', 'api_error']
        if acceptable_errors.include?(error_type)
          skip "API temporarily unavailable: #{error_msg}"
        else
          fail "API rejected Skills request: #{error_type} - #{error_msg}"
        end
      else
        # Request was accepted
        expect(result).to have_key('content')
        puts "  ✓ Skills API request accepted" if ENV['DEBUG']
      end
    end
  end

  describe 'File Save Path' do
    it 'uses correct path for documents directory' do
      # Verify the save_to_documents method uses correct paths
      require_relative '../../lib/monadic/adapters/vendors/claude_helper'

      helper_class = Class.new { include ClaudeHelper }
      helper = helper_class.new

      # The method should exist and be callable
      expect(helper).to respond_to(:save_to_documents)

      # Test with dummy data
      test_data = 'test content'
      test_filename = "test_#{Time.now.to_i}.txt"

      documents_dir = if Monadic::Utils::Environment.in_container?
                        '/monadic/data/documents'
                      else
                        File.join(Dir.home, 'monadic', 'data', 'documents')
                      end

      # Ensure directory exists
      FileUtils.mkdir_p(documents_dir)

      result = helper.save_to_documents(test_data, test_filename)

      expect(result).to be_a(Hash)
      expect(result[:path]).to include('documents')
      expect(result[:path]).to include(test_filename)
      expect(File.exist?(result[:path])).to be(true)

      # Cleanup
      File.delete(result[:path]) if File.exist?(result[:path])
    end
  end
end
