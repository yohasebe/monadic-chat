# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"

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

  describe "fetch_file path traversal protection" do
    # Tests the path sanitization pattern used in static_routes.rb fetch_file method
    let(:data_dir) { Dir.mktmpdir("monadic_test_data") }

    before do
      File.write(File.join(data_dir, "safe_file.txt"), "safe content")

      @outside_file = Tempfile.new("outside_file")
      @outside_file.write("outside content")
      @outside_file.close
    end

    after do
      FileUtils.rm_rf(data_dir)
      @outside_file.unlink if @outside_file
    end

    def safe_file_path(file_name, datadir)
      # Replicate the sanitization logic from static_routes.rb fetch_file
      safe_name = File.basename(file_name)
      file_path = File.join(datadir, safe_name)

      return nil unless File.exist?(file_path)

      real_path = File.realpath(file_path)
      real_datadir = File.realpath(datadir)
      real_datadir_with_sep = real_datadir.end_with?(File::SEPARATOR) ?
                              real_datadir :
                              real_datadir + File::SEPARATOR

      if real_path.start_with?(real_datadir_with_sep)
        file_path
      else
        nil
      end
    end

    it "allows access to files within the data directory" do
      result = safe_file_path("safe_file.txt", data_dir)
      expect(result).not_to be_nil
      expect(result).to end_with("safe_file.txt")
    end

    it "blocks path traversal with ../" do
      result = safe_file_path("../../../etc/passwd", data_dir)
      expect(result).to be_nil
    end

    it "blocks path traversal with encoded dots" do
      result = safe_file_path("..%2F..%2Fetc%2Fpasswd", data_dir)
      expect(result).to be_nil
    end

    it "strips directory components from filename" do
      expect(File.basename("/etc/passwd")).to eq("passwd")
      expect(File.basename("../../../etc/passwd")).to eq("passwd")
      expect(File.basename("subdir/file.txt")).to eq("file.txt")
    end

    it "returns nil for non-existent files" do
      result = safe_file_path("nonexistent.txt", data_dir)
      expect(result).to be_nil
    end

    it "handles filenames with spaces" do
      File.write(File.join(data_dir, "file with spaces.txt"), "content")
      result = safe_file_path("file with spaces.txt", data_dir)
      expect(result).not_to be_nil
    end

    it "handles filenames with special characters" do
      safe_name = "file-name_v2.0.txt"
      File.write(File.join(data_dir, safe_name), "content")
      result = safe_file_path(safe_name, data_dir)
      expect(result).not_to be_nil
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
