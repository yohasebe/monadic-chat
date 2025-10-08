# frozen_string_literal: true

require_relative '../../spec_helper'
require 'json'
require 'open3'
require 'timeout'

RSpec.describe 'OpenAI Video Generation (API media)', :api, :media do
  let(:script_path) { File.expand_path('../../../scripts/generators/video_generator_openai.rb', __dir__) }
  let(:test_prompt) { 'a simple yellow circle on blue background' }
  let(:api_key) { ENV['OPENAI_API_KEY'] }

  before do
    skip "RUN_MEDIA not enabled" unless ENV['RUN_MEDIA'] == 'true'
    skip "OPENAI_API_KEY not set" unless api_key && !api_key.strip.empty?
  end

  describe 'sora-2 video generation' do
    it 'generates a short video (cost-guarded, real API)', :slow do
      # Use shortest duration and lowest quality to minimize cost
      # 4 seconds, 1280x720 is the minimum for Sora
      cmd = [
        'ruby', script_path,
        '-p', test_prompt,
        '-m', 'sora-2',
        '-s', '1280x720',
        '-d', '4',
        '--max-wait', '300'  # 5 minutes max
      ]

      stdout, stderr, status = nil, nil, nil

      # Use Timeout to ensure test doesn't hang indefinitely
      Timeout.timeout(360) do  # 6 minutes total timeout
        stdout, stderr, status = Open3.capture3(*cmd)
      end

      # Parse the JSON response
      result = JSON.parse(stdout) rescue nil

      # Check for success or acceptable error states
      if result.nil?
        fail "Failed to parse JSON output. STDOUT: #{stdout}, STDERR: #{stderr}"
      end

      # Check if video generation was successful
      if result['success']
        # OpenAI returns a single video directly (not an array)
        expect(result).to have_key('filename')
        expect(result['filename']).to match(/\.mp4$/)
        expect(result).to have_key('video_id')

        # Check that the file was created
        if result['path']
          expect(File.exist?(result['path'])).to be(true), "Video file not found at #{result['path']}"
          expect(File.size(result['path'])).to be > 0, "Video file is empty"
        end
      else
        # If not successful, check for known acceptable error patterns
        error_msg = result['error'] || result['message'] || 'Unknown error'

        # Some errors are acceptable in test environment
        acceptable_errors = [
          /rate limit/i,
          /quota/i,
          /billing/i,
          /timeout/i,
          /service unavailable/i
        ]

        is_acceptable_error = acceptable_errors.any? { |pattern| error_msg.match?(pattern) }

        if is_acceptable_error
          skip "Acceptable API limitation encountered: #{error_msg}"
        else
          fail "Video generation failed with unexpected error: #{error_msg}"
        end
      end
    rescue Timeout::Error
      skip "Video generation timed out (may indicate API slowness, not a test failure)"
    end
  end

  describe 'error handling' do
    it 'handles missing prompt gracefully' do
      cmd = ['ruby', script_path, '-m', 'sora-2']
      stdout, stderr, status = Open3.capture3(*cmd)

      result = JSON.parse(stdout) rescue nil
      expect(result).not_to be_nil
      expect(result['success']).to be false
      expect(result['error']).to match(/prompt is required/i)
    end

    it 'handles invalid model gracefully' do
      cmd = [
        'ruby', script_path,
        '-p', 'test',
        '-m', 'invalid-model'
      ]
      stdout, stderr, status = Open3.capture3(*cmd)

      result = JSON.parse(stdout) rescue nil
      expect(result).not_to be_nil
      expect(result['success']).to be false
      expect(result['error']).to match(/invalid model/i)
    end
  end
end
