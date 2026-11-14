# frozen_string_literal: true

require_relative "../../spec_helper"
require_relative "../../../lib/monadic/adapters/jupyter_helper"
require_relative "../../../lib/monadic/shared_tools/jupyter_operations"

RSpec.describe "Jupyter cell results with images" do
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
