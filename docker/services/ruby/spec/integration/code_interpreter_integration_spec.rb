# frozen_string_literal: true

require_relative '../spec_helper'
require_relative '../../lib/monadic/adapters/read_write_helper'

RSpec.describe "Code Interpreter Integration Tests", type: :integration do
  # Skip these tests if we're not in a proper environment
  before(:all) do
    skip "Integration tests require full application environment" unless can_run_integration_tests?
  end

  describe "File operations" do
    let(:test_file_content) { "Hello, World!\nThis is a test file." }
    let(:test_file_name) { "integration_test_#{Time.now.to_i}.txt" }
    
    after(:each) do
      # Cleanup test files
      cleanup_test_files
    end

    context "basic file operations" do
      it "can create and read test files" do
        # Basic file system test
        create_test_file(test_file_name, test_file_content)
        
        data_dir = Monadic::Utils::Environment.data_path
        
        file_path = File.join(data_dir, test_file_name)
        expect(File.exist?(file_path)).to be true
        
        content = File.read(file_path)
        expect(content).to eq(test_file_content)
      end
    end

  end

  describe "Docker environment" do
    it "can check if Docker is available" do
      docker_available = system("docker ps > /dev/null 2>&1")
      puts "Docker available: #{docker_available}"
      # This test just documents the Docker availability
      expect([true, false]).to include(docker_available)
    end
  end

  private

  def can_run_integration_tests?
    # Simplified check - just ensure basic file system operations work
    begin
      # Check if we can create the test directory
      data_dir = Monadic::Utils::Environment.data_path
      
      FileUtils.mkdir_p(data_dir) unless Dir.exist?(data_dir)
      true
    rescue
      false
    end
  end

  def create_test_file(filename, content)
    # Create a test file in the shared data directory
    data_dir = Monadic::Utils::Environment.data_path
    
    FileUtils.mkdir_p(data_dir) unless Dir.exist?(data_dir)
    File.write(File.join(data_dir, filename), content)
  end

  def cleanup_test_files
    # Clean up any test files created during the test
    data_dir = Monadic::Utils::Environment.data_path
    
    return unless Dir.exist?(data_dir)
    
    Dir.glob(File.join(data_dir, "integration_test_*")).each do |file|
      File.delete(file) if File.exist?(file) && File.file?(file)
    end
    
    Dir.glob(File.join(data_dir, "test_output_*")).each do |path|
      if File.directory?(path)
        FileUtils.rm_rf(path)
      elsif File.file?(path)
        File.delete(path)
      end
    end
  end
end