# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"
require_relative "../../../apps/mermaid_grapher/mermaid_grapher_tools"

# The preview image is returned as _image and read by the vendor helper after
# the tool returns, so preview_mermaid must not delete it on the way out.
RSpec.describe "MermaidGrapherTools#preview_mermaid preview image retention" do
  let(:shared) { Dir.mktmpdir }
  let(:test_class) do
    Class.new do
      include MermaidGrapherTools

      def initialize(shared)
        @shared = shared
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
          File.write(File.join(@shared, "capture.png"), "png")
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
    stand_in = test_class.new(shared)
    owner.runner = ->(args, _) { stand_in.send_command(command: "web_navigator.py #{args.join(' ')}", container: "python") }
    allow(Monadic::Utils::Environment).to receive(:shared_volume).and_return(shared)
    allow(Monadic::Utils::Environment).to receive(:data_path).and_return(shared)
  end

  after { FileUtils.rm_rf(shared) }

  it "keeps this call's preview image and recent ones, and removes stale ones" do
    stale = File.join(shared, "model_view_1_aaaa.png")
    File.write(stale, "stale")
    past = Time.now - 3600
    File.utime(past, past, stale)
    recent = File.join(shared, "model_view_2_bbbb.png")
    File.write(recent, "another call, not read yet")

    result = test_class.new(shared).preview_mermaid(code: "graph TD\n  A --> B\n")

    expect(result[:success]).to be true
    expect(File.exist?(File.join(shared, result[:_image]))).to be true
    expect(File.exist?(recent)).to be true
    expect(File.exist?(stale)).to be false
  end

  it "names the preview as an image for the model only, removed once it is read" do
    result = test_class.new(shared).preview_mermaid(code: "graph TD\n  A --> B\n")
    name = result[:_image]
    File.binwrite(File.join(shared, name), "\x89PNG\r\n\x1A\n".b + "x")
    File.binwrite(File.join(shared, "chart.png"), "\x89PNG\r\n\x1A\n".b + "x")

    expect(name).to start_with(Monadic::Utils::ToolImageUtils::FOR_MODEL_PREFIX)
    expect(Monadic::Utils::ToolImageUtils.encode_image_for_api(name)).to include(media_type: "image/png")
    expect(File.exist?(File.join(shared, name))).to be false
    expect(Monadic::Utils::ToolImageUtils.encode_image_for_api("chart.png")).to include(media_type: "image/png")
    expect(File.exist?(File.join(shared, "chart.png"))).to be true
  end

  it "gives each call its own preview image" do
    tools = test_class.new(shared)
    first = tools.preview_mermaid(code: "graph TD\n  A --> B\n")
    second = tools.preview_mermaid(code: "graph TD\n  B --> C\n")

    expect(first[:_image]).not_to eq(second[:_image])
    expect(File.exist?(File.join(shared, first[:_image]))).to be true
  end
end
