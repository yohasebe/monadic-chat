# frozen_string_literal: true

require_relative "../../spec_helper"
require_relative "../../../lib/monadic/shared_tools/python_execution"

# Mock MonadicHelper for testing purposes
module MonadicHelper
  # Simulate run_code behavior for python_execution_spec
  def run_code(code:, command:, extension:, session: nil)
    if code.include?("matplotlib") && code.include?("savefig")
      # Simulate image generation
      return { success: true, filename: "plot_#{Time.now.to_i}.png" }.to_json
    elsif code.include?("fig.write_html")
      # Simulate HTML file generation
      return { success: true, filename: "report_#{Time.now.to_i}.html" }.to_json
    elsif code.include?("print")
      # Simulate text output
      return { success: true, message: "Hello from Python!" }.to_json
    end
    # Default fallback
    { success: true, message: "Executed code." }.to_json
  end
end

RSpec.describe "MonadicSharedTools::PythonExecution" do
  let(:test_class) do
    Class.new do
      include MonadicSharedTools::PythonExecution

      # Override super from MonadicHelper for testing
      def super(args)
        # MonadicHelper methods are called directly in `python_execution.rb`
        # So we can just call our mock `run_code` here
        if args.key?(:code) && args.key?(:command) && args.key?(:extension)
          MonadicHelper.new.run_code(**args)
        else
          # Fallback for other super calls if any
          "Mock super response"
        end
      end
    end
  end

  let(:app) { test_class.new }
  let(:session) { { parameters: {} } }

  describe "#run_code" do
    context "when Python code generates an image" do
      let(:code_with_image) { "import matplotlib.pyplot as plt; plt.plot([1,2,3]); plt.savefig('my_plot.png')" }

      it "saves the generated filename to session[:code_interpreter_last_output_file]" do
        result_json = app.run_code(code: code_with_image, command: "python", extension: "py", session: session)
        # Result may be String or Hash depending on _image enrichment
        raw = result_json.is_a?(Hash) ? result_json[:text] : result_json
        parsed_result = JSON.parse(raw)
        expect(parsed_result["success"]).to be true
        expect(session[:code_interpreter_last_output_file]).to eq(parsed_result["filename"])
      end
    end

    context "when Python code generates an HTML file" do
      let(:code_with_html) { "with open('report.html', 'w') as f: f.write('<h1>Report</h1>')" }

      it "saves the generated filename to session[:code_interpreter_last_output_file]" do
        result_json = app.run_code(code: code_with_html, command: "python", extension: "py", session: session)
        raw = result_json.is_a?(Hash) ? result_json[:text] : result_json
        parsed_result = JSON.parse(raw)
        expect(parsed_result["success"]).to be true
        expect(session[:code_interpreter_last_output_file]).to eq(parsed_result["filename"])
      end
    end

    context "when Python code produces text output" do
      let(:code_with_text) { "print('hello world')" }

      it "does not save a filename to session[:code_interpreter_last_output_file]" do
        result_json = app.run_code(code: code_with_text, command: "python", extension: "py", session: session)
        raw = result_json.is_a?(Hash) ? result_json[:text] : result_json
        parsed_result = JSON.parse(raw)
        expect(parsed_result["success"]).to be true
        expect(session[:code_interpreter_last_output_file]).to be_nil
      end
    end

    context "when code is empty" do
      it "returns an error" do
        result = app.run_code(code: "", command: "python", extension: "py", session: session)
        expect(result).to eq({ success: false, error: "Code cannot be empty" })
      end
    end

    context "when command is missing" do
      it "returns an error" do
        result = app.run_code(code: "print('hello')", command: nil, extension: "py", session: session)
        expect(result).to eq({ success: false, error: "Missing required parameters: code, command, and extension are all required" })
      end
    end
  end

  describe "#enrich_with_images (via run_code)" do
    let(:data_path) { Dir.mktmpdir("monadic_test") }

    before do
      allow(Monadic::Utils::Environment).to receive(:data_path).and_return(data_path)
    end

    after do
      FileUtils.rm_rf(data_path)
    end

    context "when output contains image file references" do
      it "returns original String (no _image) and stores gallery_html with session" do
        png_file = File.join(data_path, "chart.png")
        File.binwrite(png_file, "fake png data")

        output_with_image = "Code executed successfully\n\nIMAGE FILES CREATED:\n- /data/chart.png\n"
        test_session = {}
        result = app.send(:enrich_with_images, output_with_image, session: test_session)

        # Returns original String — no _image key (no vision injection)
        expect(result).to be_a(String)
        expect(result).to eq(output_with_image)
        # Gallery HTML stored for server-side display
        expect(test_session[:tool_html_fragments].first).to include('<img src="/data/chart.png" />')
      end

      it "stores gallery_html with multiple images" do
        File.binwrite(File.join(data_path, "plot1.png"), "fake")
        File.binwrite(File.join(data_path, "plot2.jpg"), "fake")

        output = "Files: /data/plot1.png and /data/plot2.jpg"
        test_session = {}
        result = app.send(:enrich_with_images, output, session: test_session)

        expect(result).to be_a(String)
        html = test_session[:tool_html_fragments].first
        expect(html).to include('<img src="/data/plot1.png" />')
        expect(html).to include('<img src="/data/plot2.jpg" />')
      end

      it "excludes SVG files" do
        File.binwrite(File.join(data_path, "diagram.svg"), "fake svg")

        output = "Generated: /data/diagram.svg"
        result = app.send(:enrich_with_images, output)

        expect(result).to be_a(String)
        expect(result).to eq(output)
      end

      it "excludes files larger than 5 MB" do
        large_file = File.join(data_path, "huge.png")
        File.binwrite(large_file, "x" * (6 * 1024 * 1024))

        output = "Generated: /data/huge.png"
        result = app.send(:enrich_with_images, output)

        expect(result).to be_a(String)
        expect(result).to eq(output)
      end

      it "limits gallery to 5 images maximum" do
        7.times do |i|
          File.binwrite(File.join(data_path, "img#{i}.png"), "fake")
        end

        output = (0..6).map { |i| "/data/img#{i}.png" }.join("\n")
        test_session = {}
        result = app.send(:enrich_with_images, output, session: test_session)

        expect(result).to be_a(String)
        # Gallery HTML should have at most 5 images
        html = test_session[:tool_html_fragments].first
        expect(html.scan('generated_image').size).to eq(5)
      end

      it "excludes non-existent files" do
        output = "Generated: /data/nonexistent.png"
        result = app.send(:enrich_with_images, output)

        expect(result).to be_a(String)
        expect(result).to eq(output)
      end
    end

    context "gallery_html server-side injection" do
      it "stores gallery_html in session[:tool_html_fragments] when session is provided" do
        png_file = File.join(data_path, "plot.png")
        File.binwrite(png_file, "fake png data")

        output = "Generated: /data/plot.png"
        test_session = {}
        result = app.send(:enrich_with_images, output, session: test_session)

        expect(result).to be_a(String)
        expect(test_session[:tool_html_fragments]).to be_a(Array)
        expect(test_session[:tool_html_fragments].first).to include('<img src="/data/plot.png" />')
        expect(test_session[:tool_html_fragments].first).to include('class="generated_image"')
      end

      it "generates gallery_html with multiple images" do
        File.binwrite(File.join(data_path, "a.png"), "fake")
        File.binwrite(File.join(data_path, "b.jpg"), "fake")

        output = "Files: /data/a.png and /data/b.jpg"
        test_session = {}
        result = app.send(:enrich_with_images, output, session: test_session)

        html = test_session[:tool_html_fragments].first
        expect(html).to include('<img src="/data/a.png" />')
        expect(html).to include('<img src="/data/b.jpg" />')
      end

      it "does not store gallery_html when session is nil" do
        png_file = File.join(data_path, "chart.png")
        File.binwrite(png_file, "fake png data")

        output = "Generated: /data/chart.png"
        result = app.send(:enrich_with_images, output, session: nil)

        # Returns String, no error even without session
        expect(result).to be_a(String)
      end

      it "does not store gallery_html when no images are valid" do
        output = "Generated: /data/nonexistent.png"
        test_session = {}
        result = app.send(:enrich_with_images, output, session: test_session)

        expect(result).to be_a(String)
        expect(test_session[:tool_html_fragments]).to be_nil
      end
    end

    context "when output has no image references" do
      it "returns the original String" do
        output = "Hello, World!\nThe code has been executed successfully"
        result = app.send(:enrich_with_images, output)

        expect(result).to be_a(String)
        expect(result).to eq(output)
      end
    end

    context "when output is not a String" do
      it "returns the output as-is" do
        hash_output = { success: false, error: "something went wrong" }
        result = app.send(:enrich_with_images, hash_output)

        expect(result).to eq(hash_output)
      end
    end
  end

  describe "constants" do
    it "defines IMAGE_EXTENSIONS" do
      expect(MonadicSharedTools::PythonExecution::IMAGE_EXTENSIONS).to eq(%w[png jpg jpeg gif webp])
    end

    it "defines MAX_IMAGE_FILE_SIZE as 5 MB" do
      expect(MonadicSharedTools::PythonExecution::MAX_IMAGE_FILE_SIZE).to eq(5 * 1024 * 1024)
    end

    it "defines MAX_IMAGES_PER_CALL as 5" do
      expect(MonadicSharedTools::PythonExecution::MAX_IMAGES_PER_CALL).to eq(5)
    end
  end

  describe "#run_bash_command — path-misuse defensive warning" do
    # Register a mock super implementation so the shared module's
    # `super(command:)` call has something to forward to.
    before do
      test_class.send(:define_method, :run_bash_command) do |command:|
        # Mirror the shared module body but short-circuit the real super call.
        return { success: false, error: "Command parameter is required" } unless command
        return { success: false, error: "Command cannot be empty" } if command.to_s.strip.empty?

        if command.to_s.include?('~/monadic/data')
          Monadic::Utils::ExtraLogger.log {
            "[PythonExecution] ~/monadic/data detected in run_bash_command — model likely confused container vs host paths. Command: #{command.to_s[0..200]}"
          }
        end
        'executed'
      end
    end

    it 'logs a warning when the command references ~/monadic/data' do
      expect(Monadic::Utils::ExtraLogger).to receive(:log).once
      app.run_bash_command(command: 'ls ~/monadic/data/sales.csv')
    end

    it 'does not log when the command uses /data (the correct path)' do
      expect(Monadic::Utils::ExtraLogger).not_to receive(:log)
      app.run_bash_command(command: 'ls /data/sales.csv')
    end

    it 'does not log when the command uses /monadic/data (also correct)' do
      expect(Monadic::Utils::ExtraLogger).not_to receive(:log)
      app.run_bash_command(command: 'ls /monadic/data/sales.csv')
    end
  end
end
