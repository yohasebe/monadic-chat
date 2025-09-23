require "spec_helper"
require 'tempfile'
require_relative "../../lib/monadic/adapters/vendors/openai_helper"
require_relative "../../lib/monadic/document_store/local_pg_vector_store"
require_relative "../../lib/monadic/utils/pdf_storage_config"

RSpec.describe "PDF Storage Routing (DocumentStore switch)" do
  let(:helper_class) do
    Class.new do
      include OpenAIHelper
    end
  end
  let(:helper) { helper_class.new }

  before do
    # Ensure CONFIG keys exist but start clean
    CONFIG["OPENAI_VECTOR_STORE_ID"] = nil
    CONFIG["PDF_DEFAULT_STORAGE"] = nil
  end

  describe "resolve_openai_vs_id" do
    it "returns session vector store id when present" do
      session = { openai_vector_store_id: "vs_sess_123" }
      expect(helper.resolve_openai_vs_id(session)).to eq("vs_sess_123")
    end

    it "falls back to ENV/CONFIG when session id is absent" do
      CONFIG["OPENAI_VECTOR_STORE_ID"] = "vs_env_456"
      session = {}
      expect(helper.resolve_openai_vs_id(session)).to eq("vs_env_456")
    end

    it "returns nil when neither session nor ENV has a Vector Store id" do
      session = {}
      CONFIG["OPENAI_VECTOR_STORE_ID"] = nil
      # Temporarily isolate data_path to an empty temp directory
      tmp_dir = Dir.mktmpdir
      begin
        original = Monadic::Utils::Environment.method(:data_path)
        Monadic::Utils::Environment.define_singleton_method(:data_path) { tmp_dir }
        expect(helper.resolve_openai_vs_id(session)).to be_nil
      ensure
        Monadic::Utils::Environment.define_singleton_method(:data_path, original)
        FileUtils.remove_entry(tmp_dir) if tmp_dir && File.directory?(tmp_dir)
      end
    end
  end

  describe "resolve_pdf_storage_mode" do
    before do
      allow(Monadic::Utils::PdfStorageConfig).to receive(:refresh_from_env).and_return(false)
    end

    it "resolves to cloud when session mode is cloud and VS is present" do
      session = { pdf_storage_mode: 'cloud', openai_vector_store_id: 'vs_abc' }
      CONFIG["PDF_DEFAULT_STORAGE"] = 'local'
      expect(helper.resolve_pdf_storage_mode(session)).to eq('cloud')
    end

    it "resolves to local when session mode is local regardless of VS presence" do
      session = { pdf_storage_mode: 'local', openai_vector_store_id: 'vs_abc' }
      CONFIG["PDF_DEFAULT_STORAGE"] = 'cloud'
      expect(helper.resolve_pdf_storage_mode(session)).to eq('local')
    end

    it "resolves to cloud when default is cloud and VS present via ENV" do
      session = {}
      CONFIG["PDF_DEFAULT_STORAGE"] = 'cloud'
      CONFIG["OPENAI_VECTOR_STORE_ID"] = 'vs_env_789'
      expect(helper.resolve_pdf_storage_mode(session)).to eq('cloud')
    end

    it "falls back to configured mode when neither source is available" do
      session = {}
      CONFIG["PDF_STORAGE_MODE"] = nil
      CONFIG["PDF_DEFAULT_STORAGE"] = 'cloud'
      CONFIG["OPENAI_VECTOR_STORE_ID"] = nil
      stub_const('EMBEDDINGS_DB', double(any_docs?: false))
      allow(Kernel).to receive(:send).and_wrap_original do |orig, method, *args|
        method == :list_pdf_titles ? [] : orig.call(method, *args)
      end
      result = helper.resolve_pdf_storage_mode(session)
      expect(result).to eq('cloud'), "expected cloud fallback, got #{result.inspect}"
    end

    it "prefers PDF_STORAGE_MODE over PDF_DEFAULT_STORAGE when set" do
      session = {}
      CONFIG["PDF_STORAGE_MODE"] = 'local'
      CONFIG["PDF_DEFAULT_STORAGE"] = 'cloud'
      # Stub local presence to true to honor local selection
      allow(helper).to receive(:resolve_openai_vs_id).and_return(nil)
      stub_const('EMBEDDINGS_DB', Object.new)
      # Define a minimal list_pdf_titles to report non-empty
      Kernel.singleton_class.send(:define_method, :list_pdf_titles) { ['a'] }
      expect(helper.resolve_pdf_storage_mode(session)).to eq('local')
      # Cleanup the temporary method to avoid side effects
      Kernel.singleton_class.send(:remove_method, :list_pdf_titles)
    end

    it "never returns 'hybrid'" do
      session = {}
      CONFIG["PDF_STORAGE_MODE"] = 'local'
      expect(helper.resolve_pdf_storage_mode(session)).not_to eq('hybrid')
    end
  end

  describe "Monadic::Utils::PdfStorageConfig" do
    it "updates CONFIG when the env file changes" do
      tmp = Tempfile.new('pdf_env')
      begin
        stub_const('Paths::ENV_PATH', tmp.path)
        prev_tracking = if Monadic::Utils::PdfStorageConfig.instance_variable_defined?(:@pdf_env_file_mtime)
          Monadic::Utils::PdfStorageConfig.instance_variable_get(:@pdf_env_file_mtime)
        else
          :__undefined__
        end
        prev_mode = CONFIG['PDF_STORAGE_MODE']
        prev_default = CONFIG['PDF_DEFAULT_STORAGE']
        CONFIG.delete('PDF_STORAGE_MODE')
        CONFIG.delete('PDF_DEFAULT_STORAGE')

        File.write(tmp.path, "PDF_STORAGE_MODE=cloud\n")
        expect(Monadic::Utils::PdfStorageConfig.refresh_from_env).to be(true)
        expect(CONFIG['PDF_STORAGE_MODE']).to eq('cloud')

        File.write(tmp.path, "PDF_STORAGE_MODE=local\nPDF_DEFAULT_STORAGE=cloud\n")
        File.utime(Time.now + 1, Time.now + 1, tmp.path)
        expect(Monadic::Utils::PdfStorageConfig.refresh_from_env).to be(true)
        expect(CONFIG['PDF_STORAGE_MODE']).to eq('local')
        expect(CONFIG['PDF_DEFAULT_STORAGE']).to eq('cloud')
      ensure
        tmp.close!
        if prev_tracking == :__undefined__
          Monadic::Utils::PdfStorageConfig.send(:remove_instance_variable, :@pdf_env_file_mtime) if Monadic::Utils::PdfStorageConfig.instance_variable_defined?(:@pdf_env_file_mtime)
        else
          Monadic::Utils::PdfStorageConfig.instance_variable_set(:@pdf_env_file_mtime, prev_tracking)
        end
        if prev_mode.nil?
          CONFIG.delete('PDF_STORAGE_MODE')
        else
          CONFIG['PDF_STORAGE_MODE'] = prev_mode
        end
        if prev_default.nil?
          CONFIG.delete('PDF_DEFAULT_STORAGE')
        else
          CONFIG['PDF_DEFAULT_STORAGE'] = prev_default
        end
      end
    end
  end

  describe "resolve_pdf_storage_mode with env reload" do
    it "reflects env changes without requiring a restart" do
      tmp = Tempfile.new('pdf_env_switch')
      begin
        allow(Monadic::Utils::PdfStorageConfig).to receive(:refresh_from_env).and_call_original
        stub_const('Paths::ENV_PATH', tmp.path)
        prev_tracking = if Monadic::Utils::PdfStorageConfig.instance_variable_defined?(:@pdf_env_file_mtime)
          Monadic::Utils::PdfStorageConfig.instance_variable_get(:@pdf_env_file_mtime)
        else
          :__undefined__
        end
        prev_mode = CONFIG['PDF_STORAGE_MODE']
        prev_default = CONFIG['PDF_DEFAULT_STORAGE']
        prev_vs = CONFIG['OPENAI_VECTOR_STORE_ID']
        CONFIG.delete('PDF_STORAGE_MODE')
        CONFIG.delete('PDF_DEFAULT_STORAGE')

        CONFIG['OPENAI_VECTOR_STORE_ID'] = 'vs_env_123'
        File.write(tmp.path, "PDF_STORAGE_MODE=cloud\n")
        File.utime(Time.now + 1, Time.now + 1, tmp.path)
        session = { pdf_cache_version: 0 }

        expect(helper.resolve_pdf_storage_mode(session)).to eq('cloud')

        # Simulate switching to local mode with local docs available
        CONFIG['OPENAI_VECTOR_STORE_ID'] = nil
        stub_const('EMBEDDINGS_DB', double(any_docs?: true))
        File.write(tmp.path, "PDF_STORAGE_MODE=local\n")
        File.utime(Time.now + 2, Time.now + 2, tmp.path)

        expect(helper.resolve_pdf_storage_mode(session)).to eq('local')
      ensure
        tmp.close!
        if prev_tracking == :__undefined__
          Monadic::Utils::PdfStorageConfig.send(:remove_instance_variable, :@pdf_env_file_mtime) if Monadic::Utils::PdfStorageConfig.instance_variable_defined?(:@pdf_env_file_mtime)
        else
          Monadic::Utils::PdfStorageConfig.instance_variable_set(:@pdf_env_file_mtime, prev_tracking)
        end
        if prev_mode.nil?
          CONFIG.delete('PDF_STORAGE_MODE')
        else
          CONFIG['PDF_STORAGE_MODE'] = prev_mode
        end
        if prev_default.nil?
          CONFIG.delete('PDF_DEFAULT_STORAGE')
        else
          CONFIG['PDF_DEFAULT_STORAGE'] = prev_default
        end
        if prev_vs.nil?
          CONFIG.delete('OPENAI_VECTOR_STORE_ID')
        else
          CONFIG['OPENAI_VECTOR_STORE_ID'] = prev_vs
        end
      end
    end
  end

  describe Monadic::DocumentStore::LocalPgVectorStore do
    it "lists titles using the private Kernel fallback" do
      store = described_class.new
      kernel_singleton = Kernel.singleton_class
      was_private = kernel_singleton.private_method_defined?(:list_pdf_titles)
      had_method = kernel_singleton.method_defined?(:list_pdf_titles) || was_private
      original = kernel_singleton.instance_method(:list_pdf_titles) if had_method

      kernel_singleton.class_eval do
        private

        def list_pdf_titles
          ['fallback_doc']
        end
      end

      begin
        titles = store.list
        expect(titles).not_to be_empty
        expect(titles.first[:title]).to eq('fallback_doc')
      ensure
        if had_method && original
          kernel_singleton.define_method(:list_pdf_titles, original)
          kernel_singleton.send(:private, :list_pdf_titles) if was_private
        else
          kernel_singleton.send(:remove_method, :list_pdf_titles)
        end
      end
    end
  end
end
