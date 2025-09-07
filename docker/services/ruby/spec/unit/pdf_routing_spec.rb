require "spec_helper"
require_relative "../../lib/monadic/adapters/vendors/openai_helper"

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
      CONFIG["PDF_DEFAULT_STORAGE"] = 'cloud'
      CONFIG["OPENAI_VECTOR_STORE_ID"] = nil
      # Ensure local presence check fails (no list_pdf_titles defined)
      expect(helper.resolve_pdf_storage_mode(session)).to eq('cloud')
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
end
