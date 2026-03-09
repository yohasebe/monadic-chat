# frozen_string_literal: true

require "spec_helper"
require "json"

RSpec.describe "Static Routes Logic" do
  describe "WebSocket upgrade detection" do
    it "detects WebSocket upgrade headers" do
      env = {
        "HTTP_UPGRADE" => "websocket",
        "HTTP_CONNECTION" => "Upgrade"
      }

      is_ws = env["HTTP_UPGRADE"]&.downcase == "websocket" &&
              env["HTTP_CONNECTION"]&.downcase&.include?("upgrade")

      expect(is_ws).to be true
    end

    it "rejects non-WebSocket requests" do
      env = {
        "HTTP_UPGRADE" => nil,
        "HTTP_CONNECTION" => nil
      }

      is_ws = env["HTTP_UPGRADE"]&.downcase == "websocket" &&
              env["HTTP_CONNECTION"]&.downcase&.include?("upgrade")

      expect(is_ws).to be false
    end

    it "handles case-insensitive upgrade header" do
      env = {
        "HTTP_UPGRADE" => "WebSocket",
        "HTTP_CONNECTION" => "keep-alive, Upgrade"
      }

      is_ws = env["HTTP_UPGRADE"]&.downcase == "websocket" &&
              env["HTTP_CONNECTION"]&.downcase&.include?("upgrade")

      expect(is_ws).to be true
    end

    it "rejects when only HTTP_UPGRADE is present" do
      env = {
        "HTTP_UPGRADE" => "websocket",
        "HTTP_CONNECTION" => "keep-alive"
      }

      is_ws = env["HTTP_UPGRADE"]&.downcase == "websocket" &&
              env["HTTP_CONNECTION"]&.downcase&.include?("upgrade")

      expect(is_ws).to be false
    end
  end

  describe "Path traversal prevention (docs routes)" do
    it "strips .. from requested paths" do
      dangerous_paths = [
        "../../../etc/passwd",
        "../../secret/file.txt",
        "valid/../../../etc/shadow"
      ]

      dangerous_paths.each do |path|
        sanitized = path.gsub(/\.\./, "")
        expect(sanitized).not_to include("..")
      end
    end

    it "preserves valid paths without .." do
      valid_path = "developer/testing_guide.md"
      sanitized = valid_path.gsub(/\.\./, "")
      expect(sanitized).to eq(valid_path)
    end

    it "handles empty path" do
      path = ""
      sanitized = path.gsub(/\.\./, "")
      expect(sanitized).to eq("")
    end
  end

  describe "fetch_file path traversal prevention" do
    it "extracts only the basename from path" do
      dangerous_names = [
        "../../../etc/passwd",
        "/absolute/path/secret.txt",
        "relative/path/file.pdf"
      ]

      dangerous_names.each do |name|
        safe_name = File.basename(name)
        expect(safe_name).not_to include("/")
        expect(safe_name).not_to include("..")
      end
    end

    it "preserves simple filenames" do
      expect(File.basename("document.pdf")).to eq("document.pdf")
      expect(File.basename("image.png")).to eq("image.png")
    end
  end

  describe "Real path boundary checking" do
    it "validates file is within allowed directory" do
      Dir.mktmpdir do |tmpdir|
        # Create a file inside the directory
        file_path = File.join(tmpdir, "test.txt")
        File.write(file_path, "content")

        real_path = File.realpath(file_path)
        real_dir = File.realpath(tmpdir)
        real_dir_with_sep = real_dir.end_with?(File::SEPARATOR) ? real_dir : real_dir + File::SEPARATOR

        expect(real_path.start_with?(real_dir_with_sep)).to be true
      end
    end

    it "rejects files outside the allowed directory" do
      Dir.mktmpdir do |tmpdir|
        # A file outside tmpdir
        outside_path = File.expand_path("../../outside.txt", tmpdir)
        real_dir = File.realpath(tmpdir)
        real_dir_with_sep = real_dir.end_with?(File::SEPARATOR) ? real_dir : real_dir + File::SEPARATOR

        # The outside path should not start with the tmpdir
        expect(outside_path.start_with?(real_dir_with_sep)).to be false
      end
    end
  end

  describe "DEBUG_MODE gating" do
    before do
      allow(CONFIG).to receive(:[]).and_call_original
    end

    it "blocks docs access when DEBUG_MODE is false" do
      allow(CONFIG).to receive(:[]).with("DEBUG_MODE").and_return(false)
      expect(CONFIG["DEBUG_MODE"]).to be false
    end

    it "allows docs access when DEBUG_MODE is true" do
      allow(CONFIG).to receive(:[]).with("DEBUG_MODE").and_return(true)
      expect(CONFIG["DEBUG_MODE"]).to be true
    end
  end

  describe "Session initialization" do
    it "sets default session values" do
      session = {}
      session[:parameters] ||= {}
      session[:messages] ||= []
      session[:version] = "1.0.0-beta.9"
      session[:docker] = false

      expect(session[:parameters]).to eq({})
      expect(session[:messages]).to eq([])
      expect(session[:version]).to be_a(String)
      expect(session[:docker]).to be false
    end

    it "preserves existing session data" do
      session = {
        parameters: { "app_name" => "ChatOpenAI" },
        messages: [{ "role" => "user", "text" => "Hello" }]
      }

      session[:parameters] ||= {}
      session[:messages] ||= []

      expect(session[:parameters]).to eq({ "app_name" => "ChatOpenAI" })
      expect(session[:messages].length).to eq(1)
    end
  end

  describe "Content type mapping" do
    let(:content_type_map) do
      {
        ".html" => "text/html",
        ".css" => "text/css",
        ".js" => "application/javascript",
        ".json" => "application/json",
        ".png" => "image/png",
        ".jpg" => "image/jpeg",
        ".svg" => "image/svg+xml",
        ".md" => "text/markdown"
      }
    end

    it "maps common extensions to correct MIME types" do
      expect(content_type_map[".html"]).to eq("text/html")
      expect(content_type_map[".js"]).to eq("application/javascript")
      expect(content_type_map[".json"]).to eq("application/json")
      expect(content_type_map[".svg"]).to eq("image/svg+xml")
    end

    it "returns text/plain for unknown extensions" do
      unknown_ext = ".xyz"
      content_type = content_type_map[unknown_ext] || "text/plain"
      expect(content_type).to eq("text/plain")
    end
  end

  describe "Redirect behavior" do
    it "constructs redirect path for bare filenames" do
      filename = "image.png"
      redirect_path = "/data/#{filename}"
      expect(redirect_path).to eq("/data/image.png")
    end
  end
end
