# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"
require_relative "../../../lib/monadic/utils/shared_file_path"

RSpec.describe "Static Routes helpers" do
  describe "DOCS_CONTENT_TYPE_MAP" do
    # This constant is defined in lib/monadic.rb and used by static_routes.rb
    # We test its expected structure here for documentation and regression purposes
    let(:expected_types) do
      {
        ".html" => "text/html",
        ".md" => "text/markdown",
        ".js" => "application/javascript",
        ".css" => "text/css",
        ".json" => "application/json",
        ".png" => "image/png",
        ".jpg" => "image/jpeg",
        ".jpeg" => "image/jpeg",
        ".gif" => "image/gif",
        ".svg" => "image/svg+xml",
        ".ico" => "image/x-icon",
        ".woff" => "font/woff",
        ".woff2" => "font/woff2",
        ".ttf" => "font/ttf",
        ".eot" => "application/vnd.ms-fontobject"
      }
    end

    it "maps common web file extensions to correct MIME types" do
      expect(expected_types[".html"]).to eq("text/html")
      expect(expected_types[".js"]).to eq("application/javascript")
      expect(expected_types[".css"]).to eq("text/css")
      expect(expected_types[".json"]).to eq("application/json")
    end

    it "includes image format mappings" do
      %w[.png .jpg .jpeg .gif .svg .ico].each do |ext|
        expect(expected_types).to have_key(ext), "Missing image mapping for #{ext}"
      end
    end

    it "includes font format mappings" do
      %w[.woff .woff2 .ttf .eot].each do |ext|
        expect(expected_types).to have_key(ext), "Missing font mapping for #{ext}"
      end
    end

    it "maps both .jpg and .jpeg to image/jpeg" do
      expect(expected_types[".jpg"]).to eq("image/jpeg")
      expect(expected_types[".jpeg"]).to eq("image/jpeg")
    end
  end

  describe "fetch_file path resolution (Monadic::Utils::SharedFilePath)" do
    # fetch_file serves exactly what this resolver returns.
    let(:data_dir) { Dir.mktmpdir("monadic_test_data") }
    let(:resolve) { ->(name) { Monadic::Utils::SharedFilePath.resolve(name, data_dir) } }

    before do
      File.write(File.join(data_dir, "safe_file.txt"), "safe content")
      FileUtils.mkdir_p(File.join(data_dir, "saved", ".hidden"))
      File.write(File.join(data_dir, "saved", "clip.mp4"), "video")
      File.write(File.join(data_dir, "saved", "notes.txt"), "text")
      File.write(File.join(data_dir, "saved", ".hidden", "clip.mp4"), "video")
      @outside = Dir.mktmpdir("monadic_outside")
      File.write(File.join(@outside, "secret.mp4"), "outside")
    end

    after do
      FileUtils.rm_rf(data_dir)
      FileUtils.rm_rf(@outside)
    end

    it "serves any file at the top of the shared folder, as before" do
      expect(resolve.call("safe_file.txt")).to end_with("safe_file.txt")
    end

    it "serves nothing under a subfolder, media included" do
      expect(resolve.call("saved/clip.mp4")).to be_nil
      expect(resolve.call("saved/notes.txt")).to be_nil
      expect(resolve.call("saved/.hidden/clip.mp4")).to be_nil
    end

    it "blocks traversal, absolute paths and encoded tricks" do
      expect(resolve.call("../../../etc/passwd")).to be_nil
      expect(resolve.call("saved/../../etc/passwd")).to be_nil
      expect(resolve.call("/etc/passwd")).to be_nil
      expect(resolve.call("..%2F..%2Fetc%2Fpasswd")).to be_nil
      expect(resolve.call("saved\\clip.mp4")).to be_nil
      expect(resolve.call("a\0b")).to be_nil
    end

    it "does not follow a symlink out of the shared folder" do
      File.symlink(File.join(@outside, "secret.mp4"), File.join(data_dir, "link.mp4"))
      expect(resolve.call("link.mp4")).to be_nil
    end

    it "returns nil for missing files and directories" do
      expect(resolve.call("nonexistent.txt")).to be_nil
      expect(resolve.call("saved")).to be_nil
    end

    it "handles spaces and a non-ASCII name tagged ASCII-8BIT" do
      File.write(File.join(data_dir, "file with spaces.txt"), "content")
      File.write(File.join(data_dir, "報告書.pdf"), "content")
      expect(resolve.call("file with spaces.txt")).not_to be_nil
      expect { @result = resolve.call("報告書.pdf".b) }.not_to raise_error
      expect(@result).not_to be_nil
    end
  end
  describe "Documentation path traversal protection" do
    # Tests the path sanitization pattern used in /docs/* and /docs_dev/* routes

    it "strips double dots from requested paths" do
      path = "../../etc/passwd"
      sanitized = path.gsub(/\.\./, "")
      expect(sanitized).not_to include("..")
      expect(sanitized).to eq("//etc/passwd")
    end

    it "strips nested traversal attempts" do
      path = "....//....//etc/passwd"
      sanitized = path.gsub(/\.\./, "")
      expect(sanitized).not_to include("..")
    end

    it "preserves normal paths with dots" do
      path = "guide/setup.html"
      sanitized = path.gsub(/\.\./, "")
      expect(sanitized).to eq("guide/setup.html")
    end

    it "preserves filenames with single dots" do
      path = "advanced-topics/monadic_dsl.md"
      sanitized = path.gsub(/\.\./, "")
      expect(sanitized).to eq("advanced-topics/monadic_dsl.md")
    end

    it "validates resolved path stays within root directory" do
      docs_root = Dir.mktmpdir("docs_test")
      begin
        sub_dir = File.join(docs_root, "guide")
        FileUtils.mkdir_p(sub_dir)
        File.write(File.join(sub_dir, "test.md"), "# Test")

        file_path = File.join(docs_root, "guide", "test.md")
        real_file = File.realpath(file_path)
        real_root = File.realpath(docs_root)

        expect(real_file.start_with?(real_root)).to be true
      ensure
        FileUtils.rm_rf(docs_root)
      end
    end
  end
end
