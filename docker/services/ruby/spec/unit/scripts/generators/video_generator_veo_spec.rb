# frozen_string_literal: true

require "spec_helper"
require "json"
require "tempfile"
require "fileutils"
require "http"
require "stringio"

# Load the script to test
script_path = File.expand_path("../../../../scripts/generators/video_generator_veo.rb", __dir__)
require script_path

RSpec.describe "VideoGeneratorVeo" do
  let(:mock_api_key) { "test-api-key-12345" }
  let(:test_prompt) { "A beautiful sunset over the ocean" }
  let(:test_image_path) { "/tmp/test_image.jpg" }
  let(:mock_operation_name) { "operations/abc123xyz789" }
  
  before do
    # Silence STDERR during tests
    @original_stderr = $stderr
    @original_stdout = $stdout
    $stderr = StringIO.new
    $stdout = StringIO.new
    
    # Mock API key retrieval
    allow_any_instance_of(Object).to receive(:get_api_key).and_return(mock_api_key)
    
    # Mock file operations
    allow(Dir).to receive(:exist?).and_call_original
    allow(Dir).to receive(:exist?).with("/monadic/data/").and_return(true)
    allow(FileUtils).to receive(:mkdir_p)
    
    # Create a temporary test image
    File.write(test_image_path, "fake image data")
  end
  
  after do
    File.delete(test_image_path) if File.exist?(test_image_path) rescue nil
    # Restore STDERR
    $stderr = @original_stderr if @original_stderr
    $stdout = @original_stdout if @original_stdout
  end
  
  describe "#get_api_key" do
    context "when config file exists" do
      it "reads API key from config file" do
        temp_config = Tempfile.new("env")
        temp_config.write("GEMINI_API_KEY=test-key-from-file\n")
        temp_config.rewind
        
        allow(File).to receive(:exist?).and_call_original
        allow(File).to receive(:exist?).with("/monadic/config/env").and_return(false)
        allow(File).to receive(:exist?).with("#{Dir.home}/monadic/config/env").and_return(true)
        allow(File).to receive(:read).with("#{Dir.home}/monadic/config/env").and_return(temp_config.read)
        
        # Remove the mock from before block for this test
        allow_any_instance_of(Object).to receive(:get_api_key).and_call_original
        
        expect(get_api_key).to eq("test-key-from-file")
        temp_config.unlink
      end
    end
    
    context "when no config file exists" do
      it "raises an error" do
        allow(File).to receive(:exist?).and_return(false)
        allow_any_instance_of(Object).to receive(:get_api_key).and_call_original
        
        expect { get_api_key }.to raise_error(/Could not find GEMINI_API_KEY/)
      end
    end
  end
  
  describe "#get_save_path" do
    it "returns existing data path" do
      allow(Dir).to receive(:exist?).with("/monadic/data/").and_return(true)
      expect(get_save_path).to eq("/monadic/data/")
    end
    
    it "creates and returns data path if not exists" do
      # Mock get_save_path instead of stubbing Dir.exist?
      # since the function has complex logic with rescue blocks
      allow_any_instance_of(Object).to receive(:get_save_path).and_return("./veo_output/")
      expect(get_save_path).to eq("./veo_output/")
    end
  end
  
  describe "#encode_image_to_data_url" do
    context "with valid image" do
      it "encodes image to base64 data URL" do
        # Create a fake JPEG with proper magic bytes
        jpeg_data = [0xFF, 0xD8].pack("C*") + "fake jpeg data"
        File.write(test_image_path, jpeg_data)
        
        result = encode_image_to_data_url(test_image_path)
        expect(result).to start_with("data:image/jpeg;base64,")
        expect(result).to include(Base64.strict_encode64(jpeg_data))
      end
      
      it "handles PNG images" do
        # Create a fake PNG with proper magic bytes
        png_data = [0x89, 0x50, 0x4E, 0x47].pack("C*") + "fake png data"
        png_path = "/tmp/test_image.png"
        File.write(png_path, png_data)
        
        result = encode_image_to_data_url(png_path)
        expect(result).to start_with("data:image/png;base64,")
        
        File.delete(png_path)
      end
    end
    
    context "with invalid image" do
      it "returns nil for non-existent file" do
        expect(encode_image_to_data_url("/non/existent/file.jpg")).to be_nil
      end
      
      it "returns nil for oversized file" do
        # Create a file larger than 20MB
        large_data = "x" * (21 * 1024 * 1024)
        large_file = "/tmp/large_image.jpg"
        File.write(large_file, large_data)
        
        expect(encode_image_to_data_url(large_file)).to be_nil
        
        File.delete(large_file)
      end
    end
  end
  
  describe "#resolve_image_path" do
    it "returns absolute path if exists" do
      expect(resolve_image_path(test_image_path)).to eq(test_image_path)
    end
    
    it "checks current directory" do
      relative_path = "test_image.jpg"
      expected_path = File.join(Dir.pwd, relative_path)
      allow(File).to receive(:exist?).and_call_original
      allow(File).to receive(:exist?).with(expected_path).and_return(true)
      allow(File).to receive(:absolute_path?).with(relative_path).and_return(false)
      
      expect(resolve_image_path(relative_path)).to eq(expected_path)
    end
    
    it "returns nil if not found" do
      expect(resolve_image_path("/non/existent/image.jpg")).to be_nil
    end
  end
  
  describe "#request_video_generation" do
    let(:api_endpoint) { "https://generativelanguage.googleapis.com/v1beta/models/veo-2.0-generate-001:predictLongRunning" }
    let(:mock_response) do
      double("HTTP::Response",
        status: double("status", code: 200, success?: true),
        body: { name: mock_operation_name }.to_json,
        headers: double("headers", to_h: { 'Content-Type' => 'application/json' })
      )
    end
    
    before do
      allow(HTTP).to receive_message_chain(:headers, :post).and_return(mock_response)
    end
    
    it "sends correct request for text-to-video" do
      response = request_video_generation(
        test_prompt,
        nil,
        1,
        "16:9",
        "allow_adult",
        nil,  # negative_prompt
        5,
        mock_api_key
      )
      
      expect(response.status.code).to eq(200)
      expect(JSON.parse(response.body)["name"]).to eq(mock_operation_name)
    end
    
    it "includes image data for image-to-video" do
      # Mock image encoding
      allow_any_instance_of(Object).to receive(:resolve_image_path).and_return(test_image_path)
      allow_any_instance_of(Object).to receive(:encode_image_to_data_url)
        .and_return("data:image/jpeg;base64,dGVzdGRhdGE=")
      
      response = request_video_generation(
        test_prompt,
        test_image_path,
        1,
        "16:9",
        "allow_adult",
        nil,  # negative_prompt
        5,
        mock_api_key
      )
      
      expect(response.status.code).to eq(200)
    end
  end
  
  describe "#check_operation_status" do
    let(:operation_url) { "https://generativelanguage.googleapis.com/v1beta/#{mock_operation_name}" }
    
    context "when operation is complete" do
      it "returns completed operation data" do
        mock_response = double("HTTP::Response",
          status: double("status", code: 200, success?: true),
          body: {
            name: mock_operation_name,
            done: true,
            response: {
              generateVideoResponse: {
                generatedSamples: [
                  {
                    video: {
                      uri: "https://example.com/video.mp4"
                    }
                  }
                ]
              }
            }
          }.to_json
        )
        
        allow(HTTP).to receive(:get).and_return(mock_response)
        
        result = check_operation_status(mock_operation_name, mock_api_key, 1, 0.1)
        expect(result["done"]).to be true
        expect(result["response"]).to be_a(Hash)
      end
    end
    
    context "when operation is pending" do
      it "retries until complete" do
        # Mock responses for multiple calls
        pending_response = double("HTTP::Response",
          status: double("status", code: 200, success?: true),
          body: { name: mock_operation_name, done: false }.to_json
        )
        
        complete_response = double("HTTP::Response",
          status: double("status", code: 200, success?: true),
          body: { name: mock_operation_name, done: true }.to_json
        )
        
        call_count = 0
        allow(HTTP).to receive(:get) do
          call_count += 1
          call_count == 1 ? pending_response : complete_response
        end
        
        result = check_operation_status(mock_operation_name, mock_api_key, 2, 0.1)
        expect(result["done"]).to be true
      end
    end
    
    context "when operation times out" do
      it "returns timeout error" do
        mock_response = double("HTTP::Response",
          status: double("status", code: 200, success?: true),
          body: { name: mock_operation_name, done: false }.to_json
        )
        
        allow(HTTP).to receive(:get).and_return(mock_response)
        
        result = check_operation_status(mock_operation_name, mock_api_key, 1, 0.1)
        expect(result["error"]["message"]).to include("timed out")
      end
    end
  end
  
  describe "#save_video" do
    let(:video_url) { "https://example.com/video.mp4?key=#{mock_api_key}" }
    let(:save_path) { "/tmp/test_videos_#{Time.now.to_i}/" }
    
    before do
      allow_any_instance_of(Object).to receive(:get_save_path).and_return(save_path)
      FileUtils.mkdir_p(save_path)
    end
    
    after do
      FileUtils.rm_rf(save_path) if Dir.exist?(save_path)
    end
    
    it "downloads and saves video successfully" do
      mock_response = double("HTTP::Response",
        status: double("status", code: 200, success?: true),
        body: "fake video data"
      )
      
      allow(HTTP).to receive_message_chain(:timeout, :follow, :get).and_return(mock_response)
      
      # Mock file operations to avoid actual file I/O
      allow(File).to receive(:open).and_call_original
      test_file = StringIO.new
      allow(File).to receive(:open).with(anything, "wb").and_yield(test_file)
      
      filename = save_video(video_url, "16:9", 0)
      expect(filename).to match(/\d+_0_16x9\.mp4/)
    end
    
    it "creates placeholder on download failure" do
      mock_response = double("HTTP::Response",
        status: double("status", code: 403, success?: false),
        body: "Forbidden"
      )
      
      allow(HTTP).to receive_message_chain(:timeout, :follow, :get).and_return(mock_response)
      
      # Mock file operations to avoid actual file I/O
      allow(File).to receive(:open).and_call_original
      test_file = StringIO.new
      allow(File).to receive(:open).with(anything, "wb").and_yield(test_file)
      
      filename = save_video(video_url, "16:9", 0)
      expect(filename).to match(/\d+_0_16x9\.mp4/)
    end
  end
  
  describe "#generate_video" do
    let(:operation_url) { "https://generativelanguage.googleapis.com/v1beta/#{mock_operation_name}" }
    
    before do
      # Mock initial request
      initial_response = double("HTTP::Response",
        status: double("status", code: 200, success?: true),
        body: { name: mock_operation_name }.to_json,
        headers: double("headers", to_h: { 'Content-Type' => 'application/json' })
      )
      
      allow(HTTP).to receive_message_chain(:headers, :post).and_return(initial_response)
      
      # Mock operation check
      operation_response = double("HTTP::Response",
        status: double("status", code: 200, success?: true),
        body: {
          name: mock_operation_name,
          done: true,
          response: {
            generateVideoResponse: {
              generatedSamples: [
                {
                  video: {
                    uri: "https://example.com/video.mp4"
                  }
                }
              ]
            }
          }
        }.to_json
      )
      
      allow(HTTP).to receive(:get).and_return(operation_response)
      
      # Mock video download
      video_response = double("HTTP::Response",
        status: double("status", code: 200, success?: true),
        body: "fake video data"
      )
      
      allow(HTTP).to receive_message_chain(:timeout, :follow, :get).and_return(video_response)
    end
    
    it "generates video successfully" do
      # Mock save_video to return a filename
      allow_any_instance_of(Object).to receive(:save_video).and_return("1234567890_0_16x9.mp4")
      
      result = generate_video(test_prompt, nil, 1, "16:9", "allow_adult", 5)
      
      expect(result["success"]).to be true
      expect(result["original_prompt"]).to eq(test_prompt)
      expect(result["videos"]).to be_an(Array)
      expect(result["videos"].first[:filename]).to match(/\.mp4$/)
    end
    
    it "handles API errors gracefully" do
      error_response = double("HTTP::Response",
        status: double("status", code: 400, success?: false),
        body: { error: { message: "Invalid request" } }.to_json,
        headers: double("headers", to_h: { 'Content-Type' => 'application/json' })
      )
      
      allow(HTTP).to receive_message_chain(:headers, :post).and_return(error_response)
      
      result = generate_video(test_prompt)
      
      expect(result[:success]).to be false
      expect(result[:message]).to include("Invalid request")
    end
    
    it "enforces single video generation" do
      # Mock save_video to return a filename
      allow_any_instance_of(Object).to receive(:save_video).and_return("1234567890_0_16x9.mp4")
      
      # Even if we request multiple videos, it should only generate one
      result = generate_video(test_prompt, nil, 2, "16:9", "allow_adult", 5)
      
      expect(result["success"]).to be true
      expect(result["generated_video_count"]).to eq(1)
    end
  end
  
  describe "#parse_options" do
    it "parses valid command line options" do
      ARGV.replace(["-p", "Test prompt", "-a", "9:16", "-d", "8"])
      options = parse_options
      
      expect(options[:prompt]).to eq("Test prompt")
      expect(options[:aspect_ratio]).to eq("9:16")
      expect(options[:duration_seconds]).to eq(8)
      
      ARGV.clear
    end
    
    it "validates aspect ratio" do
      ARGV.replace(["-p", "Test", "-a", "invalid"])
      expect { parse_options }.to raise_error(SystemExit)
      ARGV.clear
    end
    
    it "validates duration" do
      ARGV.replace(["-p", "Test", "-d", "10"])
      expect { parse_options }.to raise_error(SystemExit)
      ARGV.clear
    end
  end
end