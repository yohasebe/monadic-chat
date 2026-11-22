# frozen_string_literal: true

require "spec_helper"
require "json"
require "tmpdir"
require "fileutils"
require_relative "../../../apps/mermaid_grapher/mermaid_grapher_tools"

# The preview image is returned as _image and read by the vendor helper after
# the tool returns, so preview_mermaid must not delete it on the way out.
RSpec.describe "MermaidGrapherTools#preview_mermaid preview image retention" do
  let(:shared) { File.realpath(Dir.mktmpdir) }
  # The chat's capture folder, where the preview's files go.
  let(:capture) { "conversations/c/work/.browser" }
  let(:folder) { File.join(shared, capture) }
  let(:test_class) do
    Class.new do
      include MermaidGrapherTools

      def initialize(folder)
        @folder = folder
      end

      def run_full_validation(_code, source: nil)
        { success: true, workflow_status: "validation_passed" }
      end

      def send_command(command:, container:)
        if command.include?("--action start")
          '{"success": true, "session_id": "wd-preview"}'
        elsif command.include?("--action check_render_error")
          '{"success": true, "render_error": false}'
        elsif command.include?("--action full_screenshot")
          File.write(File.join(@folder, "capture.png"), "png")
          '{"success": true, "screenshot": "capture.png"}'
        else
          '{"success": true}'
        end
      end
    end
  end

  before do
    # The preview's browser commands go to the same stand-in.
    owner = MonadicSharedTools::BrowserOwner
    owner.reset!
    allow(owner).to receive(:observe).and_return({ sessions: [], max: 3 })
    allow(owner).to receive(:capture_dir).and_return(capture)
    FileUtils.mkdir_p(folder)
    stand_in = test_class.new(folder)
    owner.runner = ->(args, _) { stand_in.send_command(command: "web_navigator.py #{args.join(' ')}", container: "python") }
    allow(Monadic::Utils::Environment).to receive(:shared_volume).and_return(shared)
    allow(Monadic::Utils::Environment).to receive(:data_path).and_return(shared)
    allow(Monadic::Utils::Environment).to receive(:state_path).and_return(File.join(shared, ".state"))
  end

  after { FileUtils.rm_rf(shared) }

  it "keeps this call's preview image and recent ones, and removes stale ones" do
    stale = File.join(folder, "model_view_1_aaaa.png")
    File.write(stale, "stale")
    past = Time.now - 3600
    File.utime(past, past, stale)
    recent = File.join(folder, "model_view_2_bbbb.png")
    File.write(recent, "another call, not read yet")

    result = test_class.new(folder).preview_mermaid(code: "graph TD\n  A --> B\n")

    expect(result[:success]).to be true
    expect(result[:_image]).to start_with("#{capture}/")
    expect(Dir.children(shared).sort).to eq(%w[conversations])
    expect(File.exist?(File.join(shared, result[:_image]))).to be true
    expect(File.exist?(recent)).to be true
    expect(File.exist?(stale)).to be false
  end

  it "names the preview as an image for the model only, removed once it is read" do
    result = test_class.new(folder).preview_mermaid(code: "graph TD\n  A --> B\n")
    name = result[:_image]
    File.binwrite(File.join(shared, name), "\x89PNG\r\n\x1A\n".b + "x")
    File.binwrite(File.join(shared, "chart.png"), "\x89PNG\r\n\x1A\n".b + "x")

    expect(File.basename(name)).to start_with(Monadic::Utils::ToolImageUtils::FOR_MODEL_PREFIX)
    # Read for the request of the chat whose folder holds it.
    allow(Monadic::Utils::ToolImageUtils).to receive(:current_chat_folder).and_return(capture.split("/").first(2).join("/"))
    expect(Monadic::Utils::ToolImageUtils.encode_image_for_api(name)).to include(media_type: "image/png")
    expect(File.exist?(File.join(shared, name))).to be false
    expect(Monadic::Utils::ToolImageUtils.encode_image_for_api("chart.png")).to include(media_type: "image/png")
    expect(File.exist?(File.join(shared, "chart.png"))).to be true
  end

  it "makes no preview without a chat, and nothing in the shared folder" do
    allow(MonadicSharedTools::BrowserOwner).to receive(:capture_dir).and_return(nil)
    result = JSON.parse(test_class.new(folder).preview_mermaid(code: "graph TD\n  A --> B\n"))
    expect(result["success"]).to be false
    expect(Dir.children(folder)).to be_empty
    expect(Dir.children(shared)).to eq(%w[conversations])
  end

  it "gives each call its own preview image" do
    tools = test_class.new(folder)
    first = tools.preview_mermaid(code: "graph TD\n  A --> B\n")
    second = tools.preview_mermaid(code: "graph TD\n  B --> C\n")

    expect(first[:_image]).not_to eq(second[:_image])
    expect(File.exist?(File.join(shared, first[:_image]))).to be true
  end
end
