# frozen_string_literal: true

require_relative "../../spec_helper"
require "tmpdir"
require "fileutils"
require "base64"
require "json"
require "set"

require_relative "../../../lib/monadic/adapters/jupyter_helper"
require_relative "../../../lib/monadic/shared_tools/jupyter_operations"

# Regression test for the image-duplication bug fixed on 2026-04-11.
#
# Background: when `add_jupyter_cells(run: true)` was called multiple times
# in a single user turn, `extract_notebook_images` was re-saving the same
# plot PNGs under fresh timestamped filenames every call. Each call's
# gallery_html was appended to `session[:tool_html_fragments]`, which the
# html_handler joined into the final assistant text. The user ended up
# seeing the first batch's plot appear 3 times across 3 batches.
#
# The fix: `extract_notebook_images` accepts a `seen_hashes:` Set, and
# `jupyter_operations.add_jupyter_cells` passes
# `session[:_jupyter_seen_image_hashes]` so that repeated calls skip
# previously-emitted images. `html_handler` clears the tracker when
# tool_html_fragments is consumed, tying its lifetime to a single turn.
RSpec.describe "Jupyter add_jupyter_cells image deduplication" do
  let(:data_path) { Dir.mktmpdir("monadic_jupyter_dedupe_test") }

  before do
    allow(Monadic::Utils::Environment).to receive(:data_path).and_return(data_path)
  end

  after do
    FileUtils.rm_rf(data_path)
  end

  def build_notebook_json(cells)
    {
      "nbformat" => 4,
      "nbformat_minor" => 5,
      "metadata" => {},
      "cells" => cells
    }.to_json
  end

  def code_cell_with_image(png_b64)
    {
      "cell_type" => "code",
      "source" => "plt.show()",
      "outputs" => [
        {
          "output_type" => "display_data",
          "data" => { "image/png" => png_b64, "text/plain" => "<Figure>" },
          "metadata" => {}
        }
      ]
    }
  end

  # Stub MonadicHelper#add_jupyter_cells for the duration of each test so
  # that JupyterOperations#add_jupyter_cells' `super(...)` call does not
  # try to invoke the real jupyter_controller.py subprocess. The
  # MonadicHelper method is saved and restored in after blocks.
  before do
    @original_add_method = MonadicHelper.instance_method(:add_jupyter_cells)
    MonadicHelper.send(:define_method, :add_jupyter_cells) do |filename:, cells:, run: true, escaped: false, retrial: false|
      "Command has been executed successfully. Cells added to notebook at /monadic/data/#{filename}"
    end
  end

  after do
    if @original_add_method
      orig = @original_add_method
      MonadicHelper.send(:define_method, :add_jupyter_cells, orig)
    end
  end

  let(:harness) do
    obj = Object.new
    obj.extend(MonadicHelper)
    obj.extend(MonadicSharedTools::JupyterOperations)
    obj
  end

  it "does not duplicate images across multiple add_jupyter_cells calls in one turn" do
    # Phase 1: create a notebook with plot A (first batch)
    b64_a = Base64.strict_encode64("plot A data")
    nb_json_1 = build_notebook_json([code_cell_with_image(b64_a)])
    File.write(File.join(data_path, "multi.ipynb"), nb_json_1)

    session = {}

    # First add_jupyter_cells call — emits plot A
    harness.add_jupyter_cells(
      filename: "multi.ipynb",
      cells: [{ "cell_type" => "code", "source" => "plt.plot()" }],
      run: true,
      session: session
    )

    expect(session[:tool_html_fragments]).to be_an(Array)
    expect(session[:tool_html_fragments].size).to eq(1)
    expect(session[:_jupyter_seen_image_hashes].size).to eq(1)

    # Phase 2: simulate batch 2 adding a cell with NO image (print statement).
    # Plot A is still in the notebook from batch 1.
    nb_json_2 = build_notebook_json([
      code_cell_with_image(b64_a),
      {
        "cell_type" => "code",
        "source" => "print('hello')",
        "outputs" => [{ "output_type" => "stream", "name" => "stdout", "text" => "hello\n" }]
      }
    ])
    File.write(File.join(data_path, "multi.ipynb"), nb_json_2)

    # Second add_jupyter_cells call — the extractor walks the notebook and
    # finds plot A again, but plot A's hash is already in seen_hashes so
    # it is skipped. No new gallery fragment should be appended.
    harness.add_jupyter_cells(
      filename: "multi.ipynb",
      cells: [{ "cell_type" => "code", "source" => "print('hello')" }],
      run: true,
      session: session
    )

    # Still only 1 gallery fragment — no duplicate
    expect(session[:tool_html_fragments].size).to eq(1)

    # Phase 3: batch 3 adds plot B (a new image)
    b64_b = Base64.strict_encode64("plot B data")
    nb_json_3 = build_notebook_json([
      code_cell_with_image(b64_a),
      {
        "cell_type" => "code",
        "source" => "print('hello')",
        "outputs" => [{ "output_type" => "stream", "name" => "stdout", "text" => "hello\n" }]
      },
      code_cell_with_image(b64_b)
    ])
    File.write(File.join(data_path, "multi.ipynb"), nb_json_3)

    harness.add_jupyter_cells(
      filename: "multi.ipynb",
      cells: [{ "cell_type" => "code", "source" => "plt.plot()" }],
      run: true,
      session: session
    )

    # Now 2 gallery fragments: [batch1(A), batch3(B)]. Plot A was NOT
    # re-emitted in batch 3 because its hash is in seen_hashes.
    expect(session[:tool_html_fragments].size).to eq(2)
    expect(session[:_jupyter_seen_image_hashes].size).to eq(2)

    # Verify the final set of emitted <img> tags contains plot A once
    # and plot B once — total 2, not 4 (the pre-fix bug value).
    combined = session[:tool_html_fragments].join("\n")
    img_count = combined.scan(/<img /).size
    expect(img_count).to eq(2)
  end

  it "re-emits plots in a new turn after the tracker is cleared" do
    b64 = Base64.strict_encode64("plot data")
    nb_json = build_notebook_json([code_cell_with_image(b64)])
    File.write(File.join(data_path, "turn_boundary.ipynb"), nb_json)

    session = {}

    # Turn 1
    harness.add_jupyter_cells(
      filename: "turn_boundary.ipynb",
      cells: [{ "cell_type" => "code", "source" => "plt.plot()" }],
      run: true,
      session: session
    )
    expect(session[:tool_html_fragments].size).to eq(1)

    # Simulate html_handler consuming the fragments at end of turn 1
    session.delete(:tool_html_fragments)
    session.delete(:_jupyter_seen_image_hashes)

    # Turn 2 — same plot should be emitted again (fresh turn)
    harness.add_jupyter_cells(
      filename: "turn_boundary.ipynb",
      cells: [{ "cell_type" => "code", "source" => "plt.plot()" }],
      run: true,
      session: session
    )
    expect(session[:tool_html_fragments].size).to eq(1)
  end
end
