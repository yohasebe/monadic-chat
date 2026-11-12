# frozen_string_literal: true

require_relative "../../spec_helper"

# JupyterLab is started with the extensions the Python image installs
# (Plotly's renderer, widgets): core mode would leave them out, and a Plotly
# chart in a notebook would show nothing.
RSpec.describe "run_jupyter.sh" do
  let(:script) do
    File.read(File.expand_path("../../../../python/scripts/utilities/run_jupyter.sh", __dir__))
  end

  it "starts JupyterLab with the installed extensions" do
    start = script.lines.find { |line| line.include?("jupyter lab ") }
    expect(start).to include("--port=8889")
    expect(start).not_to include("--core-mode")
  end
end
