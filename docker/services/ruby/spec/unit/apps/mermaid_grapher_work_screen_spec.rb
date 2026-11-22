# frozen_string_literal: true

require_relative "../../spec_helper"
require_relative "../../../apps/mermaid_grapher/mermaid_grapher_constants"
require_relative "../../../lib/monadic/shared_tools/registry"

# Mermaid Grapher puts the diagram it checked on the work screen (as a .mmd
# file of the chat's folder) and keeps it in the chat only when it cannot.
# Every provider's variant says the same.
RSpec.describe "Mermaid Grapher and the work screen" do
  let(:dir) { File.expand_path("../../../apps/mermaid_grapher", __dir__) }
  let(:variants) { Dir.glob(File.join(dir, "mermaid_grapher_*.mdsl")) }

  it "gives every provider's variant the same instructions" do
    expect(variants.size).to eq(4)
    variants.each do |file|
      text = File.read(file)
      expect(text).to include("system_prompt MermaidGrapher::SYSTEM_PROMPT"), file
      expect(text).not_to include("system_prompt <<~"), file
    end
  end

  it "puts the checked diagram on the work screen as a .mmd file, and says what to do for each answer of the tool" do
    prompt = MermaidGrapher::SYSTEM_PROMPT
    expect(prompt).to include("call `put_on_workbench` once")
    expect(prompt).to match(/ending in `\.mmd`/)
    # Each status the tool returns (WorkbenchTools#put_on_workbench) has its reply.
    expect(prompt).to include('`"status": "shown_in_work_screen"`')
    expect(prompt).to include('`"status": "written_not_shown"`')
    expect(prompt).to include("Do not call `put_on_workbench` again to make another file")
    expect(prompt).to match(/An error \(it starts with ❌, nothing was written\)/)
    expect(prompt).not_to include("The user also sees the diagram as SVG in the chat")
  end

  it "shows the diagram in the chat when the tools are not available" do
    prompt = MermaidGrapher::SYSTEM_PROMPT
    expect(prompt).to match(/When the tools are not available, do not retry and do not call `put_on_workbench`/)
    expect(prompt).not_to include("Private")
  end

  it "names the statuses the tool really returns" do
    source = File.read(File.expand_path("../../../lib/monadic/shared_tools/workbench_tools.rb", __dir__))
    expect(source).to include("'shown_in_work_screen'")
    expect(source).to include("'written_not_shown'")
    expect(source).to include('"❌ Nothing was put on the work screen')
  end

  it "uses a tool every app is given, which draws .mmd files" do
    tools = MonadicSharedTools::Registry::TOOL_GROUPS[:workbench][:tools].map { |t| t[:name] }
    expect(tools).to include("put_on_workbench")
    require_relative "../../../lib/monadic/render_formats"
    expect(Monadic::RenderFormats.for_name("order-flow.mmd")).to eq("diagram")
  end
end
