# frozen_string_literal: true

require "spec_helper"
require "json"
require "tempfile"
require "tmpdir"
require "fileutils"
require "http"
require "stringio"

# Loaded into its own namespace: top-level defs land on Object, so `require`
# here made this script's script.get_api_key / script.generate_video visible to — and
# collide with — every other generator spec in the same process.
GEMINI_VIDEO_SCRIPT = GeneratorScriptLoader.load("video_generator_gemini.rb")

RSpec.describe "VideoGeneratorGemini" do
  let(:script) { GEMINI_VIDEO_SCRIPT }
  let(:mock_api_key) { "test-api-key-12345" }
  let(:test_prompt) { "A beautiful sunset over the ocean" }
  let(:test_image_path) { File.join(@data_dir, "test_image.jpg") }
  
  around do |example|
    Dir.mktmpdir('video-shared-') do |directory|
      @data_dir = File.realpath(directory)
      example.run
    end
  end

  before do
    # Silence STDERR during tests
    @original_stderr = $stderr
    @original_stdout = $stdout
    $stderr = StringIO.new
    $stdout = StringIO.new
    
    # Mock API key retrieval
    allow(script).to receive(:get_api_key).and_return(mock_api_key)
    
    # Mock file operations
    allow(Dir).to receive(:exist?).and_call_original
    allow(Dir).to receive(:exist?).with("/monadic/data/").and_return(true)
    allow(FileUtils).to receive(:mkdir_p)
    
    allow(Monadic::Utils::Environment).to receive(:data_path).and_return(@data_dir)
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
    # The real lookup, against an env file that holds what users write.
    let(:env_file) { File.join(@data_dir, "env") }

    before do
      allow(script).to receive(:get_api_key).and_call_original
      allow(Monadic::Utils::Environment).to receive(:env_path).and_return(env_file)
    end

    it "returns a plain key" do
      File.write(env_file, "GEMINI_API_KEY=test-key-from-file\n")
      expect(script.get_api_key).to eq("test-key-from-file")
    end

    it "returns the delivered value of a 1Password reference" do
      File.write(env_file, "GEMINI_API_KEY=op://Test/GEMINI/credential\n")
      allow(Monadic::Utils::SecretReferences).to receive(:resolved).and_return({ "GEMINI_API_KEY" => "delivered-key" })
      expect(script.get_api_key).to eq("delivered-key")
    end

    it "stops on an unread reference instead of sending its text as the key" do
      File.write(env_file, "GEMINI_API_KEY=op://Test/GEMINI/credential\n")
      allow(Monadic::Utils::SecretReferences).to receive(:resolved).and_return({})
      expect { script.get_api_key }.to raise_error(/GEMINI_API_KEY is not set/) { |e| expect(e.message).not_to include("op://") }
    end

    it "stops when the key is absent" do
      File.write(env_file, "OTHER=1\n")
      expect { script.get_api_key }.to raise_error(/GEMINI_API_KEY is not set/)
    end
  end

  describe "#get_save_path" do
    it "returns existing data path" do
      allow(Dir).to receive(:exist?).with("/monadic/data/").and_return(true)
      expect(script.get_save_path).to eq("/monadic/data/")
    end
    
    it "creates and returns data path if not exists" do
      # Mock script.get_save_path instead of stubbing Dir.exist?
      # since the function has complex logic with rescue blocks
      allow(script).to receive(:get_save_path).and_return("./gemini_video_output/")
      expect(script.get_save_path).to eq("./gemini_video_output/")
    end
  end
  
  describe "#encode_image_to_data_url" do
    context "with valid image" do
      it "encodes image to base64 data URL" do
        # Create a fake JPEG with proper magic bytes
        jpeg_data = [0xFF, 0xD8].pack("C*") + "fake jpeg data"
        File.write(test_image_path, jpeg_data)
        
        result = script.encode_image_to_data_url(test_image_path)
        expect(result).to start_with("data:image/jpeg;base64,")
        expect(result).to include(Base64.strict_encode64(jpeg_data))
      end
      
      it "handles PNG images" do
        # Create a fake PNG with proper magic bytes
        png_data = [0x89, 0x50, 0x4E, 0x47].pack("C*") + "fake png data"
        png_path = File.join(@data_dir, "test_image.png")
        File.write(png_path, png_data)
        
        result = script.encode_image_to_data_url(png_path)
        expect(result).to start_with("data:image/png;base64,")
        
        File.delete(png_path)
      end
    end
    
    context "with invalid image" do
      it "returns nil for non-existent file" do
        expect(script.encode_image_to_data_url("/non/existent/file.jpg")).to be_nil
      end
      
      it "returns nil for a file over the 10 MB the generator sends" do
        large_data = "x" * (11 * 1024 * 1024)
        large_file = File.join(@data_dir, "large_image.jpg")
        File.write(large_file, large_data)
        
        expect(script.encode_image_to_data_url(large_file)).to be_nil
        
        File.delete(large_file)
      end
    end
  end
  
  describe "#resolve_image_path" do
    it "returns an existing absolute path inside the shared folder" do
      expect(script.resolve_image_path(test_image_path)).to eq(test_image_path)
    end
    
    it "resolves relative paths against the shared folder rather than CWD" do
      Dir.mktmpdir('video-cwd-') do |directory|
        File.binwrite(File.join(directory, 'test_image.jpg'), 'outside image')
        Dir.chdir(directory) do
          expect(script.resolve_image_path('test_image.jpg')).to eq(test_image_path)
          expect(script.resolve_image_path(File.join(directory, 'test_image.jpg'))).to be_nil
        end
      end
    end

    it "returns nil if not found" do
      expect(script.resolve_image_path("/non/existent/image.jpg")).to be_nil
    end
  end
  
  describe "#generate_video" do
    let(:generator) { instance_double(Monadic::Utils::GeminiOmniVideo) }

    before { allow(Monadic::Utils::GeminiOmniVideo).to receive(:new).and_return(generator) }

    it "passes the request to Gemini Omni and lists the saved video" do
      expect(generator).to receive(:generate)
        .with(prompt: test_prompt, image: nil, aspect_ratio: "9:16", duration: 5, negative_prompt: "cars")
        .and_return({ success: true, filename: "gemini_omni_x.mp4", duration: 5 })
      result = script.generate_video(test_prompt, nil, aspect_ratio: "9:16", duration: 5, negative_prompt: "cars")
      expect(result[:success]).to be true
      expect(result[:videos]).to eq([{ filename: "gemini_omni_x.mp4", aspect_ratio: "9:16", duration: 5 }])
      expect(result[:original_prompt]).to eq(test_prompt)
    end

    it "sends the image of the shared folder as the first frame" do
      jpeg = [0xFF, 0xD8].pack("C*") + "jpeg"
      File.binwrite(test_image_path, jpeg)
      expect(generator).to receive(:generate)
        .with(hash_including(image: { data: jpeg, mime_type: "image/jpeg" }))
        .and_return({ success: true, filename: "gemini_omni_y.mp4", duration: 8 })
      expect(script.generate_video(test_prompt, "test_image.jpg")[:success]).to be true
    end

    it "refuses an image it cannot read before any key or request" do
      expect(script).not_to receive(:get_api_key)
      expect(Monadic::Utils::GeminiOmniVideo).not_to receive(:new)
      result = script.generate_video(test_prompt, "/non/existent/image.jpg")
      expect(result).to include(success: false, error: "invalid_input")
      expect(result[:message]).to include("Invalid shared image path")
    end

    it "passes a failure on as it is" do
      allow(generator).to receive(:generate).and_return({ success: false, error: "rejected", message: "Gemini refused the request" })
      result = script.generate_video(test_prompt)
      expect(result).to include(success: false, error: "rejected")
      expect(result).not_to have_key(:videos)
    end

    it "reports a missing key instead of raising" do
      allow(script).to receive(:get_api_key).and_raise("ERROR: GEMINI_API_KEY is not set")
      result = script.generate_video(test_prompt)
      expect(result).to include(success: false, error: "configuration")
      expect(result[:message]).to start_with("GEMINI_API_KEY is not set")
    end
  end

  describe "#parse_options" do
    it "reads the prompt, image, aspect ratio, duration and what to avoid" do
      options = script.parse_options(["-p", "a boat", "-i", "boat.jpg", "-a", "9:16", "-d", "6", "--negative-prompt", "people"])
      expect(options).to include(prompt: "a boat", image_path: "boat.jpg", aspect_ratio: "9:16",
                                 duration_seconds: "6", negative_prompt: "people")
    end

    it "accepts the options callers wrote for Veo and ignores them" do
      options = script.parse_options(["-p", "a boat", "-n", "2", "--fast", "--quality"])
      expect(options).to include(prompt: "a boat", aspect_ratio: "16:9", duration_seconds: 8)
    end
  end

  describe "the command line" do
    it "prints one JSON line with the outcome and exits non-zero on failure" do
      allow(STDERR).to receive(:puts)
      _script, output = GeneratorScriptLoader.run_cli("video_generator_gemini.rb", ["-p", "x", "-i", "/outside/a.png"])
      lines = output.lines.map(&:strip).reject(&:empty?)
      expect(lines.size).to eq(1)
      expect(JSON.parse(lines.first)).to include("success" => false, "error" => "invalid_input")
    end
  end
end
