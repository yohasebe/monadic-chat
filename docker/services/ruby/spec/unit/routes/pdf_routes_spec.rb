# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"
require "digest"
require_relative "../../../lib/monadic/utils/pdf_storage_config"

RSpec.describe "PDF Routes logic" do
  describe "PDF storage mode resolution cascade" do
    # Tests the mode selection logic from /api/pdf_storage_status
    # Priority: session explicit > configured+presence > any presence > configured fallback

    def resolve_mode(session_mode:, configured_mode:, cloud_present:, local_present:)
      if session_mode == 'local'
        'local'
      elsif session_mode == 'cloud' && cloud_present
        'cloud'
      elsif configured_mode == 'cloud' && cloud_present
        'cloud'
      elsif configured_mode == 'local' && local_present
        'local'
      elsif cloud_present
        'cloud'
      elsif local_present
        'local'
      else
        configured_mode
      end
    end

    context "session explicit mode" do
      it "returns local when session says local, regardless of presence" do
        result = resolve_mode(session_mode: 'local', configured_mode: 'cloud',
                              cloud_present: true, local_present: false)
        expect(result).to eq('local')
      end

      it "returns cloud when session says cloud and cloud is present" do
        result = resolve_mode(session_mode: 'cloud', configured_mode: 'local',
                              cloud_present: true, local_present: true)
        expect(result).to eq('cloud')
      end

      it "falls through when session says cloud but cloud is not present" do
        result = resolve_mode(session_mode: 'cloud', configured_mode: 'local',
                              cloud_present: false, local_present: true)
        expect(result).to eq('local')
      end
    end

    context "configured mode with presence" do
      it "returns cloud when configured cloud and cloud present" do
        result = resolve_mode(session_mode: '', configured_mode: 'cloud',
                              cloud_present: true, local_present: false)
        expect(result).to eq('cloud')
      end

      it "returns local when configured local and local present" do
        result = resolve_mode(session_mode: '', configured_mode: 'local',
                              cloud_present: false, local_present: true)
        expect(result).to eq('local')
      end
    end

    context "presence-based fallback" do
      it "prefers cloud when both are present and no session/config preference" do
        result = resolve_mode(session_mode: '', configured_mode: '',
                              cloud_present: true, local_present: true)
        expect(result).to eq('cloud')
      end

      it "returns local when only local is present" do
        result = resolve_mode(session_mode: '', configured_mode: '',
                              cloud_present: false, local_present: true)
        expect(result).to eq('local')
      end

      it "returns cloud when only cloud is present" do
        result = resolve_mode(session_mode: '', configured_mode: '',
                              cloud_present: true, local_present: false)
        expect(result).to eq('cloud')
      end
    end

    context "nothing present" do
      it "falls back to configured_mode when nothing is present" do
        result = resolve_mode(session_mode: '', configured_mode: 'local',
                              cloud_present: false, local_present: false)
        expect(result).to eq('local')
      end

      it "falls back to empty configured_mode when truly nothing" do
        result = resolve_mode(session_mode: '', configured_mode: '',
                              cloud_present: false, local_present: false)
        expect(result).to eq('')
      end
    end
  end

  describe "File hash deduplication" do
    # Tests the SHA256 + size based deduplication pattern used in POST /openai/pdf

    let(:test_dir) { Dir.mktmpdir("pdf_dedup_test") }

    after do
      FileUtils.rm_rf(test_dir)
    end

    def compute_file_hash(path)
      sha = Digest::SHA256.file(path).hexdigest
      size = File.size(path)
      "#{sha}_#{size}"
    end

    it "produces deterministic hashes for identical content" do
      path1 = File.join(test_dir, "file1.pdf")
      path2 = File.join(test_dir, "file2.pdf")
      content = "PDF content for testing"
      File.write(path1, content)
      File.write(path2, content)

      expect(compute_file_hash(path1)).to eq(compute_file_hash(path2))
    end

    it "produces different hashes for different content" do
      path1 = File.join(test_dir, "file1.pdf")
      path2 = File.join(test_dir, "file2.pdf")
      File.write(path1, "Content A")
      File.write(path2, "Content B")

      expect(compute_file_hash(path1)).not_to eq(compute_file_hash(path2))
    end

    it "includes file size in the hash to prevent collisions" do
      path = File.join(test_dir, "test.pdf")
      File.write(path, "test content")

      hash = compute_file_hash(path)
      parts = hash.split("_")

      expect(parts.size).to eq(2)
      expect(parts[0].length).to eq(64) # SHA256 hex length
      expect(parts[1].to_i).to eq(File.size(path))
    end

    it "matches dedup candidate by hash" do
      path = File.join(test_dir, "test.pdf")
      File.write(path, "dedup test content")
      file_hash = compute_file_hash(path)

      existing_files = [
        { 'file_id' => 'file-abc', 'hash' => file_hash, 'filename' => 'old.pdf' },
        { 'file_id' => 'file-def', 'hash' => 'different_hash_123', 'filename' => 'other.pdf' }
      ]

      dedup = existing_files.find { |f| f['hash'] == file_hash }
      expect(dedup).not_to be_nil
      expect(dedup['file_id']).to eq('file-abc')
    end

    it "returns nil when no hash matches" do
      existing_files = [
        { 'file_id' => 'file-abc', 'hash' => 'hash_aaa', 'filename' => 'a.pdf' }
      ]

      dedup = existing_files.find { |f| f['hash'] == 'hash_bbb' }
      expect(dedup).to be_nil
    end
  end

  describe "error_json helper" do
    # Tests the error_json format used consistently across PDF routes

    def error_json(message)
      { success: false, error: message }.to_json
    end

    it "returns valid JSON with success:false" do
      result = JSON.parse(error_json("test error"))
      expect(result["success"]).to be false
      expect(result["error"]).to eq("test error")
    end

    it "preserves error message with special characters" do
      msg = "Failed: status=403 (forbidden)"
      result = JSON.parse(error_json(msg))
      expect(result["error"]).to eq(msg)
    end

    it "handles empty error messages" do
      result = JSON.parse(error_json(""))
      expect(result["success"]).to be false
      expect(result["error"]).to eq("")
    end
  end

  describe "App key resolution" do
    # Tests the pattern for resolving app_key from session parameters

    def resolve_app_key(session_params)
      (session_params && session_params["app_name"]) || "default"
    rescue StandardError
      "default"
    end

    it "returns app_name from session parameters" do
      expect(resolve_app_key({ "app_name" => "pdf_navigator" })).to eq("pdf_navigator")
    end

    it "returns default when parameters is nil" do
      expect(resolve_app_key(nil)).to eq("default")
    end

    it "returns default when app_name is missing" do
      expect(resolve_app_key({ "model" => "gpt-5" })).to eq("default")
    end

    it "returns default when parameters is empty" do
      expect(resolve_app_key({})).to eq("default")
    end
  end

  describe "get_pdf_storage_mode" do
    # Tests the CONFIG-based mode resolution

    before do
      @prev_mode = CONFIG['PDF_STORAGE_MODE']
      @prev_default = CONFIG['PDF_DEFAULT_STORAGE']
    end

    after do
      if @prev_mode.nil?
        CONFIG.delete('PDF_STORAGE_MODE')
      else
        CONFIG['PDF_STORAGE_MODE'] = @prev_mode
      end
      if @prev_default.nil?
        CONFIG.delete('PDF_DEFAULT_STORAGE')
      else
        CONFIG['PDF_DEFAULT_STORAGE'] = @prev_default
      end
    end

    def get_pdf_storage_mode_logic
      mode = (CONFIG["PDF_STORAGE_MODE"] || CONFIG["PDF_DEFAULT_STORAGE"] || 'local').to_s.downcase
      %w[local cloud].include?(mode) ? mode : 'local'
    end

    it "returns local by default" do
      CONFIG.delete('PDF_STORAGE_MODE')
      CONFIG.delete('PDF_DEFAULT_STORAGE')
      expect(get_pdf_storage_mode_logic).to eq('local')
    end

    it "prefers PDF_STORAGE_MODE over PDF_DEFAULT_STORAGE" do
      CONFIG['PDF_STORAGE_MODE'] = 'cloud'
      CONFIG['PDF_DEFAULT_STORAGE'] = 'local'
      expect(get_pdf_storage_mode_logic).to eq('cloud')
    end

    it "falls back to PDF_DEFAULT_STORAGE when PDF_STORAGE_MODE is nil" do
      CONFIG['PDF_STORAGE_MODE'] = nil
      CONFIG['PDF_DEFAULT_STORAGE'] = 'cloud'
      expect(get_pdf_storage_mode_logic).to eq('cloud')
    end

    it "normalizes mode to lowercase" do
      CONFIG['PDF_STORAGE_MODE'] = 'CLOUD'
      expect(get_pdf_storage_mode_logic).to eq('cloud')
    end

    it "rejects invalid modes and defaults to local" do
      CONFIG['PDF_STORAGE_MODE'] = 'hybrid'
      expect(get_pdf_storage_mode_logic).to eq('local')
    end

    it "rejects empty string and defaults to local" do
      CONFIG['PDF_STORAGE_MODE'] = ''
      CONFIG['PDF_DEFAULT_STORAGE'] = ''
      expect(get_pdf_storage_mode_logic).to eq('local')
    end
  end

  describe "Vector Store ID resolution priority" do
    # Tests the fallback chain: session → app ENV → global ENV → registry → fallback meta

    def resolve_vs_id(session_vs:, app_env_vs:, env_vs:, reg_vs:, fallback_vs:)
      vs_id = session_vs
      vs_id = app_env_vs if (vs_id.nil? || vs_id.to_s.empty?) && app_env_vs
      vs_id = env_vs if (vs_id.nil? || vs_id.to_s.empty?) && env_vs && !env_vs.to_s.empty?
      vs_id = reg_vs if (vs_id.nil? || vs_id.to_s.empty?) && reg_vs
      vs_id = fallback_vs if (vs_id.nil? || vs_id.to_s.empty?) && fallback_vs
      vs_id
    end

    it "prefers session value" do
      result = resolve_vs_id(session_vs: "vs_sess", app_env_vs: "vs_app",
                             env_vs: "vs_env", reg_vs: "vs_reg", fallback_vs: "vs_fb")
      expect(result).to eq("vs_sess")
    end

    it "falls back to app ENV when session is nil" do
      result = resolve_vs_id(session_vs: nil, app_env_vs: "vs_app",
                             env_vs: "vs_env", reg_vs: "vs_reg", fallback_vs: "vs_fb")
      expect(result).to eq("vs_app")
    end

    it "falls back to global ENV when session and app ENV are nil" do
      result = resolve_vs_id(session_vs: nil, app_env_vs: nil,
                             env_vs: "vs_env", reg_vs: "vs_reg", fallback_vs: "vs_fb")
      expect(result).to eq("vs_env")
    end

    it "falls back to registry when ENV sources are nil" do
      result = resolve_vs_id(session_vs: nil, app_env_vs: nil,
                             env_vs: nil, reg_vs: "vs_reg", fallback_vs: "vs_fb")
      expect(result).to eq("vs_reg")
    end

    it "falls back to meta file when all else is nil" do
      result = resolve_vs_id(session_vs: nil, app_env_vs: nil,
                             env_vs: nil, reg_vs: nil, fallback_vs: "vs_fb")
      expect(result).to eq("vs_fb")
    end

    it "returns nil when everything is nil" do
      result = resolve_vs_id(session_vs: nil, app_env_vs: nil,
                             env_vs: nil, reg_vs: nil, fallback_vs: nil)
      expect(result).to be_nil
    end

    it "treats empty string as absent" do
      result = resolve_vs_id(session_vs: "", app_env_vs: nil,
                             env_vs: "", reg_vs: "vs_reg", fallback_vs: nil)
      expect(result).to eq("vs_reg")
    end
  end
end
