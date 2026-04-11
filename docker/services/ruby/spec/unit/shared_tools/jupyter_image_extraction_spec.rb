# frozen_string_literal: true

require_relative "../../spec_helper"
require_relative "../../../lib/monadic/adapters/jupyter_helper"
require_relative "../../../lib/monadic/shared_tools/jupyter_operations"

RSpec.describe "Jupyter Image Extraction" do
  let(:data_path) { Dir.mktmpdir("monadic_jupyter_test") }

  before do
    allow(Monadic::Utils::Environment).to receive(:data_path).and_return(data_path)
  end

  after do
    FileUtils.rm_rf(data_path)
  end

  # Create a minimal valid notebook JSON with optional image outputs
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
      "source" => "import matplotlib.pyplot as plt\nplt.plot([1,2,3])\nplt.show()",
      "outputs" => [
        {
          "output_type" => "display_data",
          "data" => {
            "image/png" => png_b64,
            "text/plain" => "<Figure size 640x480 with 1 Axes>"
          },
          "metadata" => {}
        }
      ]
    }
  end

  def code_cell_text_only
    {
      "cell_type" => "code",
      "source" => "print('hello')",
      "outputs" => [
        {
          "output_type" => "stream",
          "name" => "stdout",
          "text" => "hello\n"
        }
      ]
    }
  end

  def markdown_cell
    {
      "cell_type" => "markdown",
      "source" => "# Test"
    }
  end

  # Helper module instance for testing
  let(:helper_instance) do
    obj = Object.new
    obj.extend(MonadicHelper)
    obj
  end

  describe "MonadicHelper#extract_notebook_images" do
    context "when notebook has image outputs" do
      it "extracts PNG images from display_data outputs" do
        # A minimal valid PNG (1x1 pixel transparent)
        fake_png_b64 = Base64.strict_encode64("fake png content for test")

        nb_json = build_notebook_json([
          code_cell_text_only,
          code_cell_with_image(fake_png_b64)
        ])
        File.write(File.join(data_path, "test_nb.ipynb"), nb_json)

        result = helper_instance.extract_notebook_images(filename: "test_nb")

        expect(result).to be_an(Array)
        expect(result.size).to eq(1)
        expect(result.first).to match(/^jupyter_output_\d{8}_\d{6}_1\.png$/)
        expect(File.exist?(File.join(data_path, result.first))).to be true
      end

      it "extracts images from execute_result outputs" do
        fake_png_b64 = Base64.strict_encode64("fake png")
        cell = {
          "cell_type" => "code",
          "source" => "display(fig)",
          "outputs" => [
            {
              "output_type" => "execute_result",
              "data" => { "image/png" => fake_png_b64, "text/plain" => "<Figure>" },
              "metadata" => {},
              "execution_count" => 1
            }
          ]
        }

        nb_json = build_notebook_json([cell])
        File.write(File.join(data_path, "exec_result.ipynb"), nb_json)

        result = helper_instance.extract_notebook_images(filename: "exec_result")
        expect(result.size).to eq(1)
      end

      it "limits extraction to max_images" do
        fake_b64 = Base64.strict_encode64("fake")
        cells = 8.times.map { code_cell_with_image(fake_b64) }

        nb_json = build_notebook_json(cells)
        File.write(File.join(data_path, "many_images.ipynb"), nb_json)

        result = helper_instance.extract_notebook_images(filename: "many_images", max_images: 3)
        expect(result.size).to eq(3)
      end

      it "defaults to max 5 images" do
        fake_b64 = Base64.strict_encode64("fake")
        cells = 8.times.map { code_cell_with_image(fake_b64) }

        nb_json = build_notebook_json(cells)
        File.write(File.join(data_path, "default_limit.ipynb"), nb_json)

        result = helper_instance.extract_notebook_images(filename: "default_limit")
        expect(result.size).to eq(5)
      end

      it "skips images larger than 5 MB" do
        large_data = "x" * (6 * 1024 * 1024)
        large_b64 = Base64.strict_encode64(large_data)

        nb_json = build_notebook_json([code_cell_with_image(large_b64)])
        File.write(File.join(data_path, "large_image.ipynb"), nb_json)

        result = helper_instance.extract_notebook_images(filename: "large_image")
        expect(result).to be_empty
      end

      it "walks cells in reverse order (latest first)" do
        b64_first = Base64.strict_encode64("first cell image")
        b64_last = Base64.strict_encode64("last cell image")

        nb_json = build_notebook_json([
          code_cell_with_image(b64_first),
          code_cell_text_only,
          code_cell_with_image(b64_last)
        ])
        File.write(File.join(data_path, "reverse_order.ipynb"), nb_json)

        result = helper_instance.extract_notebook_images(filename: "reverse_order", max_images: 1)
        expect(result.size).to eq(1)

        # The single extracted image should be from the LAST cell (reverse order)
        saved_content = File.binread(File.join(data_path, result.first))
        expect(saved_content).to eq("last cell image")
      end
    end

    context "when notebook has no images" do
      it "returns empty array" do
        nb_json = build_notebook_json([code_cell_text_only, markdown_cell])
        File.write(File.join(data_path, "text_only.ipynb"), nb_json)

        result = helper_instance.extract_notebook_images(filename: "text_only")
        expect(result).to eq([])
      end
    end

    context "when notebook does not exist" do
      it "returns empty array" do
        result = helper_instance.extract_notebook_images(filename: "nonexistent")
        expect(result).to eq([])
      end
    end

    context "when notebook has invalid JSON" do
      it "returns empty array" do
        File.write(File.join(data_path, "bad.ipynb"), "this is not json")

        result = helper_instance.extract_notebook_images(filename: "bad")
        expect(result).to eq([])
      end
    end

    context "filename handling" do
      it "works with .ipynb extension provided" do
        fake_b64 = Base64.strict_encode64("test")
        nb_json = build_notebook_json([code_cell_with_image(fake_b64)])
        File.write(File.join(data_path, "with_ext.ipynb"), nb_json)

        result = helper_instance.extract_notebook_images(filename: "with_ext.ipynb")
        expect(result.size).to eq(1)
      end

      it "works without .ipynb extension" do
        fake_b64 = Base64.strict_encode64("test")
        nb_json = build_notebook_json([code_cell_with_image(fake_b64)])
        File.write(File.join(data_path, "no_ext.ipynb"), nb_json)

        result = helper_instance.extract_notebook_images(filename: "no_ext")
        expect(result.size).to eq(1)
      end
    end

    context "seen_hashes deduplication (per-turn)" do
      # Simulates the multi-batch add_jupyter_cells pattern that caused
      # the same plot to be emitted 3 times when adding 3 batches to a
      # single notebook. The seen_hashes parameter tracks PNG content
      # hashes across calls so the same plot is only saved once per turn.
      require 'set'

      it "skips images already recorded in seen_hashes" do
        fake_b64 = Base64.strict_encode64("plot A content")
        nb_json = build_notebook_json([code_cell_with_image(fake_b64)])
        File.write(File.join(data_path, "dedupe.ipynb"), nb_json)

        seen = Set.new

        # First call — image is new, should be extracted.
        first_result = helper_instance.extract_notebook_images(
          filename: "dedupe", seen_hashes: seen
        )
        expect(first_result.size).to eq(1)
        expect(seen.size).to eq(1)

        # Second call — same notebook, same image data. Should be skipped.
        second_result = helper_instance.extract_notebook_images(
          filename: "dedupe", seen_hashes: seen
        )
        expect(second_result).to be_empty
        expect(seen.size).to eq(1)  # no new hashes added
      end

      it "extracts only new images when the notebook grows" do
        b64_old = Base64.strict_encode64("plot A")
        b64_new = Base64.strict_encode64("plot B")

        # Phase 1: notebook has plot A only
        nb_json1 = build_notebook_json([code_cell_with_image(b64_old)])
        File.write(File.join(data_path, "growing.ipynb"), nb_json1)

        seen = Set.new
        first_result = helper_instance.extract_notebook_images(
          filename: "growing", seen_hashes: seen
        )
        expect(first_result.size).to eq(1)
        expect(seen.size).to eq(1)

        # Phase 2: notebook now has plot A + plot B
        nb_json2 = build_notebook_json([
          code_cell_with_image(b64_old),
          code_cell_with_image(b64_new)
        ])
        File.write(File.join(data_path, "growing.ipynb"), nb_json2)

        second_result = helper_instance.extract_notebook_images(
          filename: "growing", seen_hashes: seen
        )
        # Only plot B (the new one) should be extracted
        expect(second_result.size).to eq(1)
        expect(seen.size).to eq(2)

        # The extracted file should contain plot B data
        saved_content = File.binread(File.join(data_path, second_result.first))
        expect(saved_content).to eq("plot B")
      end

      it "extracts all images when seen_hashes is not provided (backward compat)" do
        # Existing callers that don't pass seen_hashes should continue
        # to get the full set of images each call.
        fake_b64 = Base64.strict_encode64("plot content")
        nb_json = build_notebook_json([code_cell_with_image(fake_b64)])
        File.write(File.join(data_path, "legacy.ipynb"), nb_json)

        first = helper_instance.extract_notebook_images(filename: "legacy")
        second = helper_instance.extract_notebook_images(filename: "legacy")

        expect(first.size).to eq(1)
        expect(second.size).to eq(1)  # still extracts — no dedup without seen_hashes
      end
    end
  end

  describe "MonadicHelper#get_jupyter_cells_with_results image indication" do
    it "shows [Image output] for display_data with image/png" do
      fake_b64 = Base64.strict_encode64("img")
      nb_json = build_notebook_json([code_cell_with_image(fake_b64)])
      File.write(File.join(data_path, "img_indication.ipynb"), nb_json)

      result = helper_instance.get_jupyter_cells_with_results(filename: "img_indication")
      expect(result).to be_an(Array)
      expect(result.first[:outputs]).to include("[Image output]")
    end

    it "shows [Image output] for execute_result with image/png" do
      fake_b64 = Base64.strict_encode64("img")
      cell = {
        "cell_type" => "code",
        "source" => "fig",
        "outputs" => [
          {
            "output_type" => "execute_result",
            "data" => { "image/png" => fake_b64, "text/plain" => "<Figure>" },
            "metadata" => {},
            "execution_count" => 1
          }
        ]
      }
      nb_json = build_notebook_json([cell])
      File.write(File.join(data_path, "exec_img.ipynb"), nb_json)

      result = helper_instance.get_jupyter_cells_with_results(filename: "exec_img")
      expect(result.first[:outputs]).to include("[Image output]")
    end

    it "shows text/plain for display_data without image/png" do
      cell = {
        "cell_type" => "code",
        "source" => "display(df)",
        "outputs" => [
          {
            "output_type" => "display_data",
            "data" => { "text/plain" => "DataFrame output" },
            "metadata" => {}
          }
        ]
      }
      nb_json = build_notebook_json([cell])
      File.write(File.join(data_path, "text_display.ipynb"), nb_json)

      result = helper_instance.get_jupyter_cells_with_results(filename: "text_display")
      expect(result.first[:outputs]).to include("DataFrame output")
    end
  end
end
