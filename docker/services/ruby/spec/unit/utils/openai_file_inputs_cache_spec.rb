# frozen_string_literal: true

require "spec_helper"
require "base64"
require_relative "../../../lib/monadic/utils/openai_file_inputs_cache"

RSpec.describe Monadic::Utils::OpenAIFileInputsCache do
  let(:sample_data) { Base64.strict_encode64("Hello, World!") }
  let(:sample_raw) { "Hello, World!" }
  let(:other_data) { Base64.strict_encode64("Different content") }
  let(:other_raw) { "Different content" }
  let(:session) { {} }

  describe ".compute_hash" do
    it "returns consistent hash for same data" do
      hash1 = described_class.compute_hash(sample_raw)
      hash2 = described_class.compute_hash(sample_raw)
      expect(hash1).to eq(hash2)
    end

    it "returns different hashes for different data" do
      hash1 = described_class.compute_hash(sample_raw)
      hash2 = described_class.compute_hash(other_raw)
      expect(hash1).not_to eq(hash2)
    end

    it "includes byte size in the hash key" do
      hash = described_class.compute_hash(sample_raw)
      expect(hash).to match(/_\d+$/)
    end
  end

  describe ".resolve_or_upload" do
    before do
      # Stub CONFIG
      stub_const("CONFIG", { "OPENAI_API_KEY" => "test-key", "EXTRA_LOGGING" => nil })
    end

    it "returns nil for nil data" do
      result = described_class.resolve_or_upload(session, nil, "test.pdf", "application/pdf")
      expect(result).to be_nil
    end

    it "returns nil for empty data" do
      result = described_class.resolve_or_upload(session, "", "test.pdf", "application/pdf")
      expect(result).to be_nil
    end

    it "returns nil for data exceeding 50MB" do
      # Create data that decodes to > 50MB
      large_data = Base64.strict_encode64("x" * (51 * 1024 * 1024))
      result = described_class.resolve_or_upload(session, large_data, "huge.pdf", "application/pdf")
      expect(result).to be_nil
    end

    it "uploads and caches file_id on success" do
      fake_response = instance_double(Net::HTTPOK, code: "200", body: '{"id": "file-abc123"}')
      allow_any_instance_of(Net::HTTP).to receive(:request).and_return(fake_response)

      result = described_class.resolve_or_upload(session, sample_data, "test.pdf", "application/pdf")
      expect(result).to eq("file-abc123")
      expect(session[:openai_file_inputs_cache]).to be_a(Hash)
      expect(session[:openai_file_inputs_cache].values.first[:file_id]).to eq("file-abc123")
    end

    it "returns cached file_id on second call" do
      fake_response = instance_double(Net::HTTPOK, code: "200", body: '{"id": "file-abc123"}')
      allow_any_instance_of(Net::HTTP).to receive(:request).and_return(fake_response)

      # First call uploads
      described_class.resolve_or_upload(session, sample_data, "test.pdf", "application/pdf")

      # Second call should not make HTTP request
      expect_any_instance_of(Net::HTTP).not_to receive(:request)
      result = described_class.resolve_or_upload(session, sample_data, "test.pdf", "application/pdf")
      expect(result).to eq("file-abc123")
    end

    it "returns nil on upload failure" do
      fake_response = instance_double(Net::HTTPServerError, code: "500", body: '{"error": "server error"}')
      allow_any_instance_of(Net::HTTP).to receive(:request).and_return(fake_response)

      result = described_class.resolve_or_upload(session, sample_data, "test.pdf", "application/pdf")
      expect(result).to be_nil
    end

    it "returns nil on network error" do
      allow_any_instance_of(Net::HTTP).to receive(:request).and_raise(Errno::ECONNREFUSED)

      result = described_class.resolve_or_upload(session, sample_data, "test.pdf", "application/pdf")
      expect(result).to be_nil
    end
  end

  describe ".build_multipart_body" do
    it "includes purpose and file fields" do
      body = described_class.build_multipart_body("boundary123", "file-content", "test.pdf")
      expect(body).to include('name="purpose"')
      expect(body).to include("user_data")
      expect(body).to include('name="file"')
      expect(body).to include('filename="test.pdf"')
      expect(body).to include("file-content")
    end

    it "sanitizes CRLF and quotes in filename" do
      body = described_class.build_multipart_body("boundary123", "data", "evil\r\ninjection\".pdf")
      expect(body).not_to include("\r\ninjection")
      expect(body).to include('filename="evil__injection_.pdf"')
    end

    it "sanitizes special characters in filename" do
      body = described_class.build_multipart_body("boundary123", "data", "<script>alert(1)</script>.xlsx")
      expect(body).not_to include("<script>")
      expect(body).to include('filename=')
    end

    it "uses fallback name for empty filename" do
      body = described_class.build_multipart_body("boundary123", "data", "")
      expect(body).to include('filename="document"')
    end
  end
end
