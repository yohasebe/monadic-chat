# frozen_string_literal: true

# Intentionally independent of spec_helper: no developer configuration or API.
require 'rspec'
require 'tmpdir'
require 'fileutils'
require 'open3'
require 'json'
require 'time'
require_relative '../../../lib/monadic/utils/shared_path_guard'
require_relative '../../../lib/monadic/utils/shared_file_path'
require_relative '../../../lib/monadic/adapters/read_write_helper'
require_relative '../../../lib/monadic/shared_tools/file_operations'
require_relative '../../../lib/monadic/agents/audio_transcription_agent'
require_relative '../../../lib/monadic/agents/image_analysis_agent'
require_relative '../../../lib/monadic/mcp/conduit'
require_relative '../../../apps/drawio_grapher/drawio_grapher_tools'
require_relative '../../../lib/monadic/utils/selenium_helper'
require_relative '../../../apps/auto_forge/auto_forge_debugger'
require_relative '../../../lib/monadic/adapters/jupyter_helper'
require_relative '../../../lib/monadic/adapters/selenium_helper'
require_relative '../../support/generator_script_loader'

RSpec.describe 'Tool input boundaries' do
  let(:guard) { Monadic::Utils::SharedPathGuard }
  let(:helper) { Class.new { include MonadicSharedTools::FileOperations }.new }
  let(:audio) { Class.new { include AudioTranscriptionAgent }.new }
  let(:vision) { Class.new { include ImageAnalysisAgent }.new }
  let(:drawio) { Class.new { include DrawIOGrapher }.new }
  let(:conduit) { Monadic::MCP::Conduit }

  around do |example|
    Dir.mktmpdir('tool-paths-') do |directory|
      @sandbox = File.realpath(directory)
      @root = File.join(@sandbox, 'shared')
      @outside = File.join(@sandbox, 'outside')
      FileUtils.mkdir_p([@root, @outside])
      example.run
    end
  end

  before do
    stub_const('CONFIG', {})
    stub_const('Monadic::VectorStore::BackendError', Class.new(StandardError))
    allow(Monadic::Utils::Environment).to receive(:data_path).and_return(@root)
    allow(Monadic::Utils::Environment).to receive(:shared_volume).and_return(@root)
    allow(Monadic::Utils::Environment).to receive(:in_container?).and_return(false)
    allow(conduit).to receive(:required_analysis_provider).and_return('openai')
    allow(Monadic::MCP::CostGuard).to receive(:ensure_within!)
    allow(Monadic::MCP::CostGuard).to receive(:record)
    allow(Monadic::MCP::CostGuard).to receive(:status).and_return({})
    allow(drawio).to receive(:sleep)
    allow(File).to receive(:read).and_call_original
    # Fail before any accidental real provider call.
    allow(HTTP).to receive(:headers) { raise 'Unexpected HTTP request' }
    allow(helper).to receive(:send_command) { raise 'Unexpected command' }
  end

  def fixture(name, root: @root, text: 'fixture')
    path = File.join(root, name)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, text)
    path
  end

  def outside_inputs(extension)
    outside = fixture("private#{extension}", root: @outside)
    File.symlink(@outside, File.join(@root, 'escape')) unless File.symlink?(File.join(@root, 'escape'))
    File.symlink(outside, File.join(@root, "linked#{extension}"))
    [outside, "../outside/private#{extension}", "escape/private#{extension}", "linked#{extension}",
     "escape/missing/deep/file#{extension}", "./../outside/private#{extension}"]
  end

  def shell_names(extension)
    ['$(printf INJECTED > sentinel)', '`printf INJECTED > sentinel`',
     'x"; printf INJECTED > sentinel; #', "x\"\nprintf INJECTED > sentinel\n#", "a'b", 'a;b'].map { |s| s + extension }
  end

  # Execute only a harmless shell function standing in for the real command.
  # Substitution/redirection would still run, so sentinel detects injection.
  def shell_arguments(command, executable)
    stub = "function #{executable} { printf '%s\\0' \"$@\"; }; "
    stdout, stderr, status = Open3.capture3('bash', '-c', stub + command, chdir: @root)
    expect(status.success?).to be(true), stderr
    expect(File.exist?(File.join(@root, 'sentinel'))).to be(false)
    stdout.split("\0")
  end

  def generator(name)
    path = File.expand_path("../../../scripts/generators/#{name}", __dir__)
    Object.new.tap { |script| script.instance_eval(File.read(path), path) }
  end

  describe 'shared path guard' do
    it 'rejects external files, traversal, links, dangling links and prefix siblings' do
      paths = outside_inputs('.txt')
      File.symlink(File.join(@outside, 'missing'), File.join(@root, 'dangling'))
      paths += ['dangling/new/file.txt', '/monadic/database/file.txt', "bad\0.txt", 'a/../file.txt']
      paths.each do |path|
        expect(guard.resolve_in_shared(path, must_exist: false)).to be_nil
        expect(helper.validate_file_path(path)).to be_nil
      end
    end

    it 'resolves missing descendants through the nearest real ancestor' do
      FileUtils.mkdir_p(File.join(@root, 'real'))
      File.symlink(File.join(@root, 'real'), File.join(@root, 'alias'))
      expect(helper.validate_file_path('alias/new/deep/file.txt')).to eq(File.join(@root, 'real/new/deep/file.txt'))
    end

    it 'supports a symlinked shared root without leaking host paths into container arguments' do
      alias_root = File.join(@sandbox, 'shared-alias')
      File.symlink(@root, alias_root)
      allow(Monadic::Utils::Environment).to receive(:data_path).and_return(alias_root)
      result = helper.write_file_to_shared_folder(filepath: 'sub/new.txt', content: 'text')
      expect(result[:success]).to be(true)
      expect(result[:filepath]).to eq('sub/new.txt')
      expect(result[:full_path]).to eq('/monadic/data/sub/new.txt')
      expect(guard.command_path('sub/new.txt', container: 'python')).to eq('/monadic/data/sub/new.txt')
    end

    it 'supports shared-relative and mount paths, Unicode, spaces and internal symlinks' do
      path = fixture('日本語 folder/file name.PNG')
      File.symlink(File.dirname(path), File.join(@root, 'alias'))
      ['日本語 folder/file name.PNG', path, '/monadic/data/日本語 folder/file name.PNG', 'alias/file name.PNG'].each do |name|
        expect(guard.resolve_in_shared(name, extensions: guard::IMAGE_EXTENSIONS)).to eq(path)
        expect(guard.command_path(name, container: 'python')).to eq('/monadic/data/日本語 folder/file name.PNG')
      end
      allow(Monadic::Utils::Environment).to receive(:in_container?).and_return(true)
      expect(guard.resolve_in_shared('/monadic/data/日本語 folder/file name.PNG')).to eq(path)
    end

    it 'agrees with download validation about symlinks, while allowing tool subfolders' do
      outside_inputs('.png')
      expect(Monadic::Utils::SharedFilePath.resolve('linked.png', @root)).to be_nil
      expect(guard.resolve_in_shared('linked.png')).to be_nil
      file = fixture('sub/picture.png')
      expect(guard.resolve_in_shared('sub/picture.png')).to eq(file)
      expect(Monadic::Utils::SharedFilePath.resolve('sub/picture.png', @root)).to be_nil
    end

    it 'checks both alias and real extensions and rejects non-files' do
      fixture('secret.txt')
      File.symlink(File.join(@root, 'secret.txt'), File.join(@root, 'alias.png'))
      FileUtils.mkdir_p(File.join(@root, 'directory.png'))
      %w[alias.png secret.txt directory.png].each do |name|
        expect(guard.resolve_in_shared(name, extensions: guard::IMAGE_EXTENSIONS)).to be_nil
      end
    end
  end

  describe 'document readers' do
    { fetch_text_from_file: ['file', 'content_fetcher.rb', '.txt', 'ruby'],
      fetch_text_from_pdf: ['pdf', 'pdf2txt.py', '.pdf', 'python'],
      fetch_text_from_office: ['file', 'office2txt.py', '.docx', 'python'] }.each do |method, (key, executable, extension, container)|
      it "#{method}: treats shell syntax as one literal filename" do
        (shell_names(extension) + ["日本語 folder/space name#{extension}", "-option#{extension}"]).each do |name|
          path = fixture(name)
          allow(helper).to receive(:send_command) do |command:, container:, **_, &block|
            args = shell_arguments(command, executable)
            expected = container == 'python' ? '/monadic/data/' + name : path
            expect(args.first).to eq(expected)
            block ? block.call('document text', '', double(success?: true)) : 'document text'
          end
          expect(helper.public_send(method, key.to_sym => name)).to eq('document text')
        end
      end

      it "#{method}: rejects external paths before executing a command" do
        outside_inputs(extension).each do |path|
          expect(helper.public_send(method, key.to_sym => path)).to start_with('Error:')
        end
        expect(helper).not_to have_received(:send_command)
      end
    end

    it 'reports failed stdout-only conversion and successful-exit office not-found as errors' do
      fixture('document.txt')
      fixture('document.docx')
      allow(helper).to receive(:send_command) do |**_, &block|
        block ? block.call('ERROR: binary file', '', double(success?: false)) : 'Error occurred: '
      end
      expect(helper.fetch_text_from_file(file: 'document.txt')).to match(/Error: .+/)
      allow(helper).to receive(:send_command) do |**_, &block|
        stdout = 'The specified file could not be found: file'
        block ? block.call(stdout, '', double(success?: true)) : stdout
      end
      expect(helper.fetch_text_from_office(file: 'document.docx')).to start_with('Error:')
    end

    it 'does not mistake ordinary text containing an error message for a command failure' do
      fixture('document.txt')
      allow(helper).to receive(:send_command) do |**_, &block|
        block ? block.call('ERROR: example documentation', '', double(success?: true)) : 'ERROR: example documentation'
      end
      expect(helper.fetch_text_from_file(file: 'document.txt')).to eq('ERROR: example documentation')
    end
  end

  describe 'shared writes and diagrams' do
    it 'does not create missing parents through an external symlink' do
      outside_inputs('.txt').each do |path|
        expect(helper.write_file_to_shared_folder(filepath: path, content: 'overwrite')[:success]).to be(false)
      end
      expect(File.read(File.join(@outside, 'private.txt'))).to eq('fixture')
      expect(File.exist?(File.join(@outside, 'missing'))).to be(false)
    end

    it 'rechecks the path after mkdir_p before writing' do
      target = File.join(@root, 'new')
      allow(FileUtils).to receive(:mkdir_p).with(target) { File.symlink(@outside, target) }
      result = helper.write_file_to_shared_folder(filepath: 'new/escape.txt', content: 'overwrite')
      expect(result[:success]).to be(false)
      expect(File.exist?(File.join(@outside, 'escape.txt'))).to be(false)
    end

    it 'writes and appends valid Unicode subfolder names' do
      result = helper.write_file_to_shared_folder(filepath: '日本語 folder/new/file name.txt', content: 'first')
      expect(result[:success]).to be(true)
      expect(helper.write_file_to_shared_folder(filepath: result[:filepath], content: 'second', mode: 'append')[:success]).to be(true)
      expect(File.read(File.join(@root, '日本語 folder/new/file name.txt'))).to eq('firstsecond')
    end

    it 'uses shell metacharacters literally in shared writes and diagrams' do
      shell_names('.txt').each do |name|
        expect(helper.write_file_to_shared_folder(filepath: name, content: 'literal')[:success]).to be(true)
        expect(File.read(File.join(@root, name))).to eq('literal')
      end
      shell_names('.drawio').each do |name|
        expect(drawio.write_drawio_file(content: '<mxfile/>', filename: name)).to include('saved successfully')
        expect(File.file?(File.join(@root, name))).to be(true)
      end
      expect(File.exist?(File.join(@root, 'sentinel'))).to be(false)
    end

    %i[write_drawio_file preview_drawio].each do |method|
      it "#{method}: refuses external paths and never starts a preview" do
        allow(drawio).to receive(:send_command) { raise 'Unexpected preview command' }
        outside_inputs('.drawio').each do |path|
          expect(drawio.public_send(method, content: '<mxfile/>', filename: path)).to start_with('❌')
        end
        expect(File.read(File.join(@outside, 'private.drawio'))).to eq('fixture')
        expect(drawio).not_to have_received(:send_command)
      end
    end

    it 'writes legitimate diagrams and never returns backtraces on write failure' do
      FileUtils.mkdir_p(File.join(@root, '日本語 folder'))
      result = drawio.write_drawio_file(content: '<mxfile/>', filename: '日本語 folder/space name')
      expect(result).to include('saved successfully')
      allow(File).to receive(:open).and_raise(Errno::EACCES, 'private diagnostic')
      result = drawio.write_drawio_file(content: '<mxfile/>', filename: 'denied')
      expect(result).to start_with('❌')
      expect(result).not_to match(/Backtrace|private diagnostic|\.rb:/)
    end
  end

  describe 'media and MCP inputs' do
    it 'rejects audio outside the shared folder or with a forbidden extension' do
      expect(Monadic::Utils::ProviderCapabilities).not_to receive(:resolve)
      (outside_inputs('.mp3') + [fixture('not_audio.txt')] + shell_names('.mp3')).each do |path|
        expect(audio.send(:resolve_audio_path, path)).to start_with('ERROR:')
        expect(audio.audio_transcription_agent(audio_path: path)).to start_with('ERROR:')
      end
    end

    it 'rejects images before reading any external bytes' do
      paths = outside_inputs('.png') + [fixture('not_image.txt')] + shell_names('.png')
      expect(File).not_to receive(:binread)
      paths.each { |path| expect(vision.send(:prepare_image_for_analysis, path)).to start_with('ERROR:') }
    end

    it 'resolves from the shared folder rather than CWD and accepts genuine media' do
      path = fixture('日本語 folder/sound name.MP3')
      expect(audio.send(:resolve_audio_path, '日本語 folder/sound name.MP3')).to eq(path)
      fixture('image name.png', text: 'image bytes')
      expect(vision.send(:prepare_image_for_analysis, './image name.png')[:base64]).to eq(Base64.strict_encode64('image bytes'))
      fixture('cwd.mp3', root: @outside)
      fixture('cwd.png', root: @outside)
      Dir.chdir(@outside) do
        expect(audio.send(:resolve_audio_path, 'cwd.mp3')).to start_with('ERROR:')
        expect(vision.send(:prepare_image_for_analysis, 'cwd.png')).to start_with('ERROR:')
      end
    end

    { handle_analyze_image: '.png', handle_transcribe_audio: '.mp3', handle_import_kb: '.pdf' }.each do |method, extension|
      it "#{method}: rejects external files before invoking agents or import" do
        expect(conduit).not_to receive(:agent_host)
        expect(conduit).not_to receive(:extract_pdf_chunks)
        paths = outside_inputs(extension) + [fixture('wrong.txt')] + shell_names(extension)
        paths.each do |path|
          expect { conduit.public_send(method, 'path' => path, 'prompt' => 'describe', 'title' => 'test') }.to raise_error(ArgumentError)
        end
      end
    end

    it 'passes canonical valid media paths to MCP agents' do
      image_path = fixture('日本語 folder/image name.png')
      audio_path = fixture('日本語 folder/audio name.mp3')
      host = double('agent')
      expect(host).to receive(:image_analysis_agent).with(message: 'describe', image_path: image_path).and_return('image')
      expect(host).to receive(:audio_transcription_agent).with(audio_path: audio_path, model: nil, response_format: 'text', lang_code: nil).and_return('audio')
      allow(conduit).to receive(:agent_host).and_return(host)
      expect(conduit.handle_analyze_image('path' => '日本語 folder/image name.png', 'prompt' => 'describe')[:success]).to be(true)
      expect(conduit.handle_transcribe_audio('path' => '日本語 folder/audio name.mp3')[:success]).to be(true)
    end

    it 'passes a canonical shared PDF to import and rejects CWD PDFs' do
      pdf = fixture('日本語 folder/file name.pdf')
      allow(conduit).to receive(:extract_pdf_chunks).and_call_original
      expect(conduit).to receive(:extract_pdf_chunks).with(pdf).and_return([{ text: 'text' }])
      store = double(store_embeddings: 'doc')
      allow(conduit).to receive(:kb_store).and_return(store)
      expect(conduit.handle_import_kb('path' => '日本語 folder/file name.pdf', 'title' => 'test')[:doc_id]).to eq('doc')
      fixture('cwd.pdf', root: @outside)
      Dir.chdir(@outside) do
        expect { conduit.extract_pdf_chunks('cwd.pdf') }.to raise_error(ArgumentError)
      end
    end
  end

  describe 'generator local inputs' do
    %w[image_generator_openai.rb video_generator_gemini.rb].each do |script_name|
      it "#{script_name}: rejects external images through the actual CLI" do
        path = fixture('private.png', root: @outside)
        expect(File).not_to receive(:read).with('/monadic/config/env')
        expect(File).not_to receive(:read).with(File.join(Dir.home, 'monadic/config/env'))
        expect(File).not_to receive(:binread).with(path)
        args = ['-p', 'test', '-i', path]
        args += ['-o', 'edit'] if script_name == 'image_generator_openai.rb'
        allow(STDERR).to receive(:puts)
        _script, output = GeneratorScriptLoader.run_cli(script_name, args)
        expect(output).to include('Invalid shared image path', 'false')
      end
    end

    it 'rejects OpenAI image and mask paths before credentials or HTTP are touched' do
      script = generator('image_generator_openai.rb')
      allow(script).to receive(:image_request_problem).and_return(nil)
      expect(script).not_to receive(:get_api_key)
      paths = outside_inputs('.png') + [fixture('wrong.txt')] + shell_names('.png')
      paths.each do |path|
        expect(script.generate_image(operation: 'edit', images: [path])[:success]).to be(false)
        expect(script.generate_image(operation: 'edit', images: [], mask: path)[:success]).to be(false)
      end
    end

    it 'accepts shared image and mask files and normalizes them before credentials' do
      script = generator('image_generator_openai.rb')
      allow(script).to receive(:image_request_problem).and_return(nil)
      fixture('日本語 folder/image name.png')
      fixture('mask.png')
      expect(script).to receive(:get_api_key) { throw :validated }
      result = catch(:validated) do
        script.generate_image(operation: 'edit', images: ['日本語 folder/image name.png'], mask: 'mask.png')
        :rejected
      end
      expect(result).to be_nil
    end

    it 'rejects video generator external images and forbidden extensions without reading bytes' do
      script = generator('video_generator_gemini.rb')
      paths = outside_inputs('.png') + [fixture('wrong.txt')] + shell_names('.png')
      expect(File).not_to receive(:binread)
      expect(script).not_to receive(:get_api_key)
      paths.each do |path|
        expect(script.resolve_image_path(path)).to be_nil
        expect(script.encode_image_to_data_url(path)).to be_nil
        expect(script.generate_video('test', path)[:success]).to be(false)
      end
    end

    it 'encodes a shared Unicode image and does not resolve CWD images' do
      script = generator('video_generator_gemini.rb')
      path = fixture('日本語 folder/image name.png', text: "\x89PNG".b + 'x' * 1024)
      expect(script.resolve_image_path('日本語 folder/image name.png')).to eq(path)
      expect(script.encode_image_to_data_url('日本語 folder/image name.png')).to start_with('data:image/png;base64,')
      fixture('cwd.png', root: @outside)
      Dir.chdir(@outside) { expect(script.resolve_image_path('cwd.png')).to be_nil }
    end
  end

  describe 'Python command callers' do
    %i[run_jupyter_cells restart_jupyter_kernel].each do |method|
      it "#{method}: passes notebook names as literal arguments" do
        (shell_names('.ipynb') + ['日本語 folder/space name.ipynb']).each do |name|
          fixture(name)
          allow(helper).to receive(:send_command) do |command:, **_|
            args = shell_arguments(command, 'jupyter')
            expect(args).to include('/monadic/data/' + name)
            true
          end
          expect(helper.public_send(method, filename: name)).not_to start_with('Error:')
        end
      end

      it "#{method}: rejects external notebooks before invoking Python" do
        outside_inputs('.ipynb').each do |path|
          expect(helper.public_send(method, filename: path)).to start_with('Error:')
        end
        expect(helper).not_to have_received(:send_command)
      end
    end

    it 'passes Selenium URLs as literal arguments even with shell syntax' do
      shell_names('').each do |payload|
        url = 'https://example.invalid/' + payload
        allow(helper).to receive(:send_command) do |command:, **_|
          args = shell_arguments(command, 'webpage_fetcher.py')
          expect(args[args.index('--url') + 1]).to eq(url)
        end
        helper.selenium_fetch(url: url)
      end
    end

    it 'quotes debugger arguments on the send_command route' do
      debugger = AutoForge::Debugger.new
      (shell_names('.html') + ['日本語 folder/space name.html']).each do |name|
        path = fixture(name)
        allow(debugger).to receive(:send_command) do |command:, **_|
          expect(shell_arguments(command, 'debug_html.py')).to eq(['/monadic/data/' + name, '--json'])
          '{"success":true}'
        end
        expect(debugger.send(:execute_debug_script, path)['success']).to be(true)
      end
    end

    it 'uses argv without a shell on the debugger standalone route' do
      debugger = AutoForge::Debugger.new
      # Another spec adds send_command to SeleniumHelper at file load time.
      # A standalone debugger has no such method; isolate that shape locally.
      debugger.singleton_class.undef_method(:send_command) if debugger.respond_to?(:send_command)
      expect(debugger).not_to receive(:`)
      name = shell_names('.html').first
      path = fixture(name)
      expect(Open3).to receive(:capture2e).with(
        'docker', 'exec', '-w', '/monadic/data', 'monadic-chat-python-container',
        'python', '/monadic/scripts/utilities/debug_html.py', '/monadic/data/' + name, '--json'
      ).and_return(['{"success":true}', double(success?: true)])
      expect(debugger.send(:execute_debug_script, path)['success']).to be(true)
    end

    it 'rejects debugger external inputs without copying or starting a container' do
      debugger = AutoForge::Debugger.new
      expect(debugger).not_to receive(:check_selenium_or_error)
      expect(debugger).not_to receive(:send_command)
      expect(Open3).not_to receive(:capture2e)
      expect(FileUtils).not_to receive(:cp)
      outside_inputs('.html').each do |path|
        expect(debugger.send(:execute_debug_script, path)['success']).to be(false)
        expect(debugger.debug_html(path)[:success]).to be(false)
      end
    end
  end
end
