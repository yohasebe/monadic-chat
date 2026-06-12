# frozen_string_literal: true

require 'spec_helper'
require 'json'
require 'tmpdir'
require 'monadic/library'

RSpec.describe Monadic::Library::FileImporter do
  let(:schema) { Monadic::Library::Schema }

  around do |example|
    Dir.mktmpdir do |dir|
      @tmp = dir
      example.run
    end
  end

  def write_temp(name, content)
    path = File.join(@tmp, name)
    File.write(path, content)
    path
  end

  describe '.build_conversation (Markdown)' do
    it 'reads .md files and dispatches to MarkdownImporter' do
      path = write_temp('notes.md', "# Title\n\nBody paragraph one. " * 10)
      conv = described_class.build_conversation(path: path)
      expect(schema.valid?(conv)).to be true
      expect(conv.dig('conversation_metadata', 'content_type')).to eq('markdown')
      expect(conv.dig('conversation_metadata', 'source')).to eq('markdown:notes.md')
    end

    it 'handles .markdown extension' do
      path = write_temp('doc.markdown', "# H\n\nbody. " * 10)
      conv = described_class.build_conversation(path: path)
      expect(conv.dig('conversation_metadata', 'content_type')).to eq('markdown')
    end
  end

  describe '.build_conversation (Code)' do
    it 'reads .rb files and dispatches to CodeImporter' do
      path = write_temp('demo.rb', "class Foo\n  def bar\n    1\n  end\nend\n")
      conv = described_class.build_conversation(path: path)
      expect(schema.valid?(conv)).to be true
      expect(conv.dig('conversation_metadata', 'content_type')).to eq('code')
      expect(conv.dig('conversation_metadata', 'topics')).to include('ruby')
    end

    it 'handles Rakefile (basename detection)' do
      path = write_temp('Rakefile', "task :default do\n  puts 'hi'\nend\n")
      conv = described_class.build_conversation(path: path)
      expect(conv.dig('conversation_metadata', 'topics')).to include('ruby')
    end
  end

  describe '.build_conversation (PDF)' do
    let(:fake_pdf_json) do
      {
        'title' => 'Faked PDF',
        'author' => 'Test Suite',
        'page_count' => 3,
        'markdown' => "# Section\n\n" + ('Paragraph body. ' * 30)
      }.to_json
    end

    before do
      allow(described_class).to receive(:run_python_extractor).and_return(fake_pdf_json)
    end

    it 'invokes the python extractor and dispatches to PdfImporter' do
      path = write_temp('paper.pdf', "%PDF-1.4 fake\n")
      conv = described_class.build_conversation(path: path)
      expect(schema.valid?(conv)).to be true
      expect(conv.dig('conversation_metadata', 'content_type')).to eq('pdf')
      expect(conv.dig('conversation_metadata', 'title')).to eq('Faked PDF')
      expect(described_class).to have_received(:run_python_extractor)
        .with(described_class::PDF_EXTRACTOR, path)
    end

    # The Quality Pack fallback must not be silent: an opted-in user whose
    # extractor container is down would otherwise get pdfplumber-quality
    # imports indefinitely with no way to notice (the beta.16 extractor
    # startup bug stayed invisible for this exact reason).
    context 'Quality Pack degradation reporting' do
      before do
        allow(Monadic::Utils::DegradationNotifier).to receive(:report)
      end

      it 'reports when the user opted in but the extractor service is down' do
        allow(described_class).to receive(:extractor_opted_in?).and_return(true)
        allow(described_class).to receive(:extractor_service_available?).and_return(false)
        path = write_temp('paper.pdf', "%PDF-1.4 fake\n")
        described_class.build_conversation(path: path)
        expect(Monadic::Utils::DegradationNotifier).to have_received(:report)
          .with(hash_including(component: 'extractor'))
        expect(described_class).to have_received(:run_python_extractor)
      end

      it 'does not report when the user never opted in (normal fallback)' do
        allow(described_class).to receive(:extractor_opted_in?).and_return(false)
        allow(described_class).to receive(:extractor_service_available?).and_return(false)
        path = write_temp('paper.pdf', "%PDF-1.4 fake\n")
        described_class.build_conversation(path: path)
        expect(Monadic::Utils::DegradationNotifier).not_to have_received(:report)
      end

      it 'does not report when the extractor service is healthy' do
        allow(described_class).to receive(:extractor_service_available?).and_return(true)
        allow(described_class).to receive(:extract_via_service).and_return(fake_pdf_json)
        path = write_temp('paper.pdf', "%PDF-1.4 fake\n")
        described_class.build_conversation(path: path)
        expect(Monadic::Utils::DegradationNotifier).not_to have_received(:report)
      end
    end
  end

  describe '.build_conversation (Office)' do
    let(:fake_docx_json) do
      {
        'title' => 'Plan',
        'format' => 'docx',
        'markdown' => "# Plan\n\nBody. " * 10
      }.to_json
    end

    before do
      allow(described_class).to receive(:run_python_extractor).and_return(fake_docx_json)
    end

    it 'invokes the python extractor for .docx and dispatches to OfficeImporter' do
      path = write_temp('plan.docx', "PK\x03\x04 fake")
      conv = described_class.build_conversation(path: path)
      expect(schema.valid?(conv)).to be true
      expect(conv.dig('conversation_metadata', 'content_type')).to eq('document')
      expect(conv.dig('conversation_metadata', 'topics')).to include('docx')
      expect(described_class).to have_received(:run_python_extractor)
        .with(described_class::OFFICE_EXTRACTOR, path)
    end

    it 'recognises .xlsx and .pptx extensions' do
      %w[data.xlsx deck.pptx].each do |name|
        path = write_temp(name, "PK\x03\x04 fake")
        described_class.build_conversation(path: path)
        expect(described_class).to have_received(:run_python_extractor)
          .with(described_class::OFFICE_EXTRACTOR, path)
      end
    end
  end

  describe '.build_conversation (unsupported)' do
    it 'raises UnsupportedFormatError for unknown extensions' do
      path = write_temp('mystery.xyz', 'opaque blob')
      expect { described_class.build_conversation(path: path) }
        .to raise_error(Monadic::Library::FileImporter::UnsupportedFormatError, /\.xyz/)
    end

    it 'raises UnsupportedFormatError when no extension at all' do
      path = write_temp('mystery', 'opaque blob')
      expect { described_class.build_conversation(path: path) }
        .to raise_error(Monadic::Library::FileImporter::UnsupportedFormatError)
    end
  end

  describe '.run_python_extractor (error path)' do
    it 'wraps non-zero exit in ExtractionError' do
      fake_status = instance_double(Process::Status, success?: false)
      allow(Open3).to receive(:capture3).and_return(['', 'boom', fake_status])
      expect { described_class.run_python_extractor('/dev/null', '/tmp/missing.pdf') }
        .to raise_error(Monadic::Library::FileImporter::ExtractionError, /boom/)
    end
  end

  describe '.extractor_service_available? (HTTP gate)' do
    it 'returns false when EXTRACTOR_SERVICE env is unset' do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with('EXTRACTOR_SERVICE').and_return(nil)
      expect(described_class.extractor_service_available?).to be false
    end

    it 'returns false when env is set but the service health probe fails' do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with('EXTRACTOR_SERVICE').and_return('true')
      fake_client = instance_double(Monadic::Extractor::Client, health: false)
      allow(Monadic::Extractor::Client).to receive(:new).and_return(fake_client)
      expect(described_class.extractor_service_available?).to be false
    end

    it 'returns true when env is set and the service is healthy' do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with('EXTRACTOR_SERVICE').and_return('true')
      fake_client = instance_double(Monadic::Extractor::Client, health: true)
      allow(Monadic::Extractor::Client).to receive(:new).and_return(fake_client)
      expect(described_class.extractor_service_available?).to be true
    end

    it 'never raises even when the underlying client raises' do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with('EXTRACTOR_SERVICE').and_return('true')
      allow(Monadic::Extractor::Client).to receive(:new).and_raise(RuntimeError, 'boom')
      expect(described_class.extractor_service_available?).to be false
    end
  end

  describe '.import_pdf (extractor_service preferred when available)' do
    let(:service_response) do
      {
        'title' => 'Docling-extracted Paper',
        'author' => 'Researcher',
        'page_count' => 5,
        'markdown' => "# Abstract\n\n" + ('Body content. ' * 30),
        'extractor_meta' => { 'pipeline' => 'docling-2.x', 'duration_ms' => 4321 }
      }
    end

    it 'routes through Extractor::Client when service_available? is true' do
      allow(described_class).to receive(:extractor_service_available?).and_return(true)
      fake_client = instance_double(Monadic::Extractor::Client)
      allow(Monadic::Extractor::Client).to receive(:new).and_return(fake_client)
      expect(fake_client).to receive(:extract).with(hash_including(format: 'pdf')).and_return(service_response)
      expect(described_class).not_to receive(:run_python_extractor)

      path = write_temp('paper.pdf', "%PDF-1.4 fake\n")
      conv = described_class.build_conversation(path: path)
      expect(conv.dig('conversation_metadata', 'title')).to eq('Docling-extracted Paper')
      expect(conv.dig('conversation_metadata', 'content_type')).to eq('pdf')
    end

    it 'falls back to subprocess when service is unavailable' do
      allow(described_class).to receive(:extractor_service_available?).and_return(false)
      fallback_json = { 'title' => 'Fallback', 'page_count' => 1, 'markdown' => 'Body. ' * 50 }.to_json
      expect(described_class).to receive(:run_python_extractor).and_return(fallback_json)

      path = write_temp('paper.pdf', "%PDF-1.4 fake\n")
      conv = described_class.build_conversation(path: path)
      expect(conv.dig('conversation_metadata', 'title')).to eq('Fallback')
    end

    it 'raises ExtractionError when the service is "available" but extract fails' do
      allow(described_class).to receive(:extractor_service_available?).and_return(true)
      fake_client = instance_double(Monadic::Extractor::Client)
      allow(Monadic::Extractor::Client).to receive(:new).and_return(fake_client)
      allow(fake_client).to receive(:extract)
        .and_raise(Monadic::Extractor::Client::ExtractionFailedError, 'bad PDF')

      path = write_temp('paper.pdf', "%PDF-1.4 fake\n")
      expect { described_class.build_conversation(path: path) }
        .to raise_error(Monadic::Library::FileImporter::ExtractionError, /bad PDF/)
    end
  end

  describe '.supported_extensions' do
    it 'returns extensions starting with a dot' do
      exts = described_class.supported_extensions
      expect(exts).to all(start_with('.'))
      expect(exts).to include('.md', '.pdf', '.docx', '.xlsx', '.pptx', '.rb', '.py')
    end
  end
end
