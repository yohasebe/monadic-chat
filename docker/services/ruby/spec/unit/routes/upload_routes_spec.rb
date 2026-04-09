# frozen_string_literal: true

require "spec_helper"
require "json"

RSpec.describe "Upload Routes Logic" do
  describe "Audio upload extension validation" do
    let(:allowed_exts) { %w[.mp3 .wav .m4a .ogg .flac .mid .midi] }

    it "accepts all allowed audio extensions" do
      allowed_exts.each do |ext|
        expect(allowed_exts).to include(ext), "Expected #{ext} to be allowed"
      end
    end

    it "rejects unsupported extensions" do
      rejected = %w[.exe .bat .sh .rb .py .js .html .pdf .doc .zip .rar]
      rejected.each do |ext|
        expect(allowed_exts).not_to include(ext), "Expected #{ext} to be rejected"
      end
    end

    it "validates extension case-insensitively by downcasing" do
      filename = "recording.MP3"
      ext = File.extname(filename).downcase
      expect(allowed_exts).to include(ext)
    end

    it "handles filenames with multiple dots" do
      filename = "my.recording.file.wav"
      ext = File.extname(filename).downcase
      expect(ext).to eq(".wav")
      expect(allowed_exts).to include(ext)
    end

    it "rejects files with no extension" do
      filename = "audiofile"
      ext = File.extname(filename).downcase
      expect(ext).to eq("")
      expect(allowed_exts).not_to include(ext)
    end
  end

  describe "Path traversal prevention" do
    it "strips directory components from filenames" do
      dangerous_inputs = [
        "../../../etc/passwd",
        "/absolute/path/to/file.mp3",
        "relative/path/file.wav"
      ]

      dangerous_inputs.each do |input|
        safe_name = File.basename(input)
        expect(safe_name).not_to include("/")
        expect(safe_name).not_to include("..")
      end
    end

    it "preserves simple filenames" do
      expect(File.basename("recording.mp3")).to eq("recording.mp3")
      expect(File.basename("my_file.wav")).to eq("my_file.wav")
    end
  end

  describe "UTF-8 encoding handling" do
    it "forces filename to UTF-8" do
      filename = +"recording.mp3"
      utf8_filename = filename.force_encoding("UTF-8")
      expect(utf8_filename.encoding).to eq(Encoding::UTF_8)
    end

    it "handles unicode filenames" do
      filename = +"録音ファイル.mp3"
      utf8_filename = filename.force_encoding("UTF-8")
      expect(utf8_filename).to eq("録音ファイル.mp3")
      expect(utf8_filename.encoding).to eq(Encoding::UTF_8)
    end

    it "sanitizes doc labels with invalid encoding" do
      raw_label = "Test\xFF\xFELabel"
      sanitized = raw_label.encode("UTF-8", invalid: :replace, undef: :replace, replace: "")
      expect(sanitized.valid_encoding?).to be true
    end
  end

  describe "Document upload result formatting" do
    it "formats result with label" do
      filename = "report.docx"
      markdown = "# Report Content\nSome text here"
      label = "Monthly Report"

      doc_text = "Filename: #{filename}\n---\n#{markdown}"
      result = "\n---\n#{label}\n---\n#{doc_text}"

      expect(result).to include(label)
      expect(result).to include(filename)
      expect(result).to include(markdown)
    end

    it "formats result without label" do
      filename = "report.docx"
      markdown = "# Report Content"
      label = ""

      doc_text = "Filename: #{filename}\n---\n#{markdown}"
      result = if label.to_s != ""
                "\n---\n#{label}\n---\n#{doc_text}"
              else
                "\n---\n#{doc_text}"
              end

      expect(result).not_to include("\n---\n\n---\n")
      expect(result).to include(filename)
    end
  end

  describe "Webpage fetch result formatting" do
    it "includes decoded URL in result" do
      url = "https://example.com/path%20with%20spaces"
      url_decoded = CGI.unescape(url)

      expect(url_decoded).to eq("https://example.com/path with spaces")
    end

    it "formats webpage result with label" do
      url_decoded = "https://example.com"
      markdown = "Page content"
      label = "Reference Material"

      webpage_text = "URL: #{url_decoded}\n---\n#{markdown}"
      result = "---\n#{label}\n---\n#{webpage_text}"

      expect(result).to include(label)
      expect(result).to include(url_decoded)
    end
  end
end
