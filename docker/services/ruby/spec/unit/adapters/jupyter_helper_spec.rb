  let(:app) { test_class.new }
  let(:session) { { parameters: {} } }

  describe "#create_jupyter_notebook" do
    before do
      allow(Monadic::Utils::Environment).to receive(:data_path).and_return("/test/data")
      allow(app).to receive(:send_command).and_return({ success: true, message: "Notebook created successfully" }.to_json)
      allow(JSON).to receive(:parse).and_call_original # Ensure JSON.parse works as expected for actual JSON strings
    end

    it "creates a new Jupyter notebook and saves its filename to session[:current_notebook_filename]" do
      notebook_name = "new_test_notebook.ipynb"
      result_json = app.create_jupyter_notebook(filename: notebook_name, session: session)
      result = JSON.parse(result_json)
      
      expect(result["success"]).to be true
      expect(session[:current_notebook_filename]).to eq(notebook_name)
      expect(app).to have_received(:send_command).with(hash_including(command: include("create_jupyter_notebook"), command: include(notebook_name)))
    end

    context "when filename is empty" do
      it "returns error message" do
        result = app.create_jupyter_notebook(filename: "", session: session)
        expect(result).to eq({ success: false, error: "Filename is required and cannot be empty." })
      end
    end
  end

  describe "#get_jupyter_cells_with_results" do
    before do
      allow(Monadic::Utils::Environment).to receive(:data_path).and_return("/test/data")
      allow(File).to receive(:exist?).and_return(true)
      allow(File).to receive(:read).and_return('{"cells": []}')
      allow(JSON).to receive(:parse).and_return({"cells" => []})
    end

    context "when filename has .ipynb extension" do
      it "does not add another .ipynb extension" do
        app.get_jupyter_cells_with_results(filename: "notebook_20250925_051036.ipynb", session: session)
        expect(File).to have_received(:exist?).with("/test/data/notebook_20250925_051036.ipynb")
      end
    end

    context "when filename does not have .ipynb extension" do
      it "adds .ipynb extension" do
        app.get_jupyter_cells_with_results(filename: "notebook_20250925_051036", session: session)
        expect(File).to have_received(:exist?).with("/test/data/notebook_20250925_051036.ipynb")
      end
    end

    context "when filename is empty and no current notebook in session" do
      it "returns error message" do
        session[:current_notebook_filename] = nil
        result = app.get_jupyter_cells_with_results(filename: "", session: session)
        expect(result).to eq({ success: false, error: "Filename is required and cannot be empty (or current notebook not set in session)." })
      end
    end

    context "when filename is empty but current notebook in session" do
      it "uses the filename from session" do
        session[:current_notebook_filename] = "session_notebook.ipynb"
        app.get_jupyter_cells_with_results(filename: "", session: session)
        expect(File).to have_received(:exist?).with("/test/data/session_notebook.ipynb")
      end
    end
  end

  describe "#add_jupyter_cells" do
    before do
      allow(Monadic::Utils::Environment).to receive(:in_container?).and_return(false)
      allow(File).to receive(:exist?).and_return(true)
      allow(File).to receive(:basename).and_return("notebook.ipynb")
      allow(app).to receive(:send_command).and_return({ success: true, message: "Cells added successfully" }.to_json)
      allow(JSON).to receive(:parse).and_call_original
    end

    context "when filename has .ipynb extension" do
      it "does not add another .ipynb extension" do
        valid_cells = [{ "cell_type" => "code", "source" => "print('hello')" }]
        app.add_jupyter_cells(filename: "test_20250925.ipynb", cells: valid_cells, session: session)
        # Verify that send_command is called with the correct filename (no double .ipynb)
        expect(app).to have_received(:send_command).with(
          hash_including(command: include("test_20250925.ipynb"))
        )
        # Ensure no double extension
        expect(app).not_to have_received(:send_command).with(
          hash_including(command: include(".ipynb.ipynb"))
        )
      end
    end

    context "when filename is empty but current notebook in session" do
      it "uses the filename from session" do
        session[:current_notebook_filename] = "session_notebook.ipynb"
        app.add_jupyter_cells(filename: nil, cells: valid_cells, session: session)
        expect(app).to have_received(:send_command).with(
          hash_including(command: include("session_notebook.ipynb"))
        )
      end
    end

    context "when filename is empty and no current notebook in session" do
      it "returns an error" do
        session[:current_notebook_filename] = nil
        valid_cells = [{ "cell_type" => "code", "source" => "print('hello')" }]
        result = app.add_jupyter_cells(filename: nil, cells: valid_cells, session: session)
        expect(result).to eq({ success: false, error: "Filename is required and cannot be empty (or current notebook not set in session)." })
      end
    end
  end

  describe "#delete_jupyter_cell" do
    before do
      allow(Monadic::Utils::Environment).to receive(:in_container?).and_return(false)
      allow(File).to receive(:exist?).and_return(true)
      allow(app).to receive(:send_command).and_return({ success: true }.to_json)
      allow(JSON).to receive(:parse).and_call_original
    end

    context "when filename is empty but current notebook in session" do
      it "uses the filename from session" do
        session[:current_notebook_filename] = "session_notebook.ipynb"
        app.delete_jupyter_cell(filename: nil, index: 0, session: session)
        expect(app).to have_received(:send_command).with(
          hash_including(command: include("session_notebook.ipynb"))
        )
      end
    end

    context "when filename is empty and no current notebook in session" do
      it "returns an error" do
        session[:current_notebook_filename] = nil
        result = app.delete_jupyter_cell(filename: nil, index: 0, session: session)
        expect(result).to eq({ success: false, error: "Filename is required and cannot be empty (or current notebook not set in session)." })
      end
    end

    context "when filename is empty and no current notebook in session" do
      it "returns an error for non-integer index" do
        result = app.delete_jupyter_cell(filename: "notebook.ipynb", index: "abc", session: session)
        expect(result).to eq({ success: false, error: "Index must be a non-negative integer." })
      end
    end
  end

  describe "#update_jupyter_cell" do
    before do
      allow(Monadic::Utils::Environment).to receive(:in_container?).and_return(false)
      allow(File).to receive(:exist?).and_return(true)
      allow(app).to receive(:send_command).and_return({ success: true }.to_json)
      allow(JSON).to receive(:parse).and_call_original
    end

    context "when filename is empty but current notebook in session" do
      it "uses the filename from session" do
        session[:current_notebook_filename] = "session_notebook.ipynb"
        app.update_jupyter_cell(filename: nil, index: 0, content: "new code", session: session)
        expect(app).to have_received(:send_command).with(
          hash_including(command: include("session_notebook.ipynb"))
        )
      end
    end

    context "when filename is empty and no current notebook in session" do
      it "returns an error" do
        session[:current_notebook_filename] = nil
        result = app.update_jupyter_cell(filename: nil, index: 0, content: "new code", session: session)
        expect(result).to eq({ success: false, error: "Filename is required and cannot be empty (or current notebook not set in session)." })
      end
    end

    context "when index is invalid" do
      it "returns an error for negative index" do
        result = app.update_jupyter_cell(filename: "notebook.ipynb", index: -1, content: "new code", session: session)
        expect(result).to eq({ success: false, error: "Index must be a non-negative integer." })
      end

      it "returns an error for non-integer index" do
        result = app.update_jupyter_cell(filename: "notebook.ipynb", index: "abc", content: "new code", session: session)
        expect(result).to eq({ success: false, error: "Index must be a non-negative integer." })
      end
    end

    context "when content is empty" do
      it "returns an error" do
        result = app.update_jupyter_cell(filename: "notebook.ipynb", index: 0, content: nil, session: session)
        expect(result).to eq({ success: false, error: "Content is required." })
      end
    end

    context "when cell_type is invalid" do
      it "returns an error" do
        result = app.update_jupyter_cell(filename: "notebook.ipynb", index: 0, content: "new code", cell_type: "invalid", session: session)
        expect(result).to eq({ success: false, error: "Cell type must be 'code' or 'markdown'." })
      end
    end
  end

  describe "#execute_and_fix_jupyter_cells" do
    before do
      allow(Monadic::Utils::Environment).to receive(:in_container?).and_return(false)
      allow(File).to receive(:exist?).and_return(true)
      allow(app).to receive(:send_command).and_return({ success: true }.to_json)
      allow(JSON).to receive(:parse).and_call_original
    end

    context "when filename is empty but current notebook in session" do
      it "uses the filename from session" do
        session[:current_notebook_filename] = "session_notebook.ipynb"
        app.execute_and_fix_jupyter_cells(filename: nil, session: session)
        expect(app).to have_received(:send_command).with(
          hash_including(command: include("session_notebook.ipynb"))
        )
      end
    end

    context "when filename is empty and no current notebook in session" do
      it "returns an error" do
        session[:current_notebook_filename] = nil
        result = app.execute_and_fix_jupyter_cells(filename: nil, session: session)
        expect(result).to eq({ success: false, error: "Filename is required and cannot be empty (or current notebook not set in session)." })
      end
    end

    context "when max_retries is invalid" do
      it "returns an error for non-integer" do
        result = app.execute_and_fix_jupyter_cells(filename: "notebook.ipynb", max_retries: "abc", session: session)
        expect(result).to eq({ success: false, error: "Max retries must be a positive integer." })
      end
    end
  end

  describe "#restart_jupyter_kernel" do
    before do
      allow(Monadic::Utils::Environment).to receive(:in_container?).and_return(false)
      allow(File).to receive(:exist?).and_return(true)
      allow(app).to receive(:send_command).and_return({ success: true }.to_json)
      allow(JSON).to receive(:parse).and_call_original
    end

    context "when filename is empty but current notebook in session" do
      it "uses the filename from session" do
        session[:current_notebook_filename] = "session_notebook.ipynb"
        app.restart_jupyter_kernel(filename: nil, session: session)
        expect(app).to have_received(:send_command).with(
          hash_including(command: include("session_notebook.ipynb"))
        )
      end
    end

    context "when filename is empty and no current notebook in session" do
      it "returns an error" do
        session[:current_notebook_filename] = nil
        result = app.restart_jupyter_kernel(filename: nil, session: session)
        expect(result).to eq({ success: false, error: "Filename is required and cannot be empty (or current notebook not set in session)." })
      end
    end
  end

  describe "#interrupt_jupyter_execution" do
    before do
      allow(Monadic::Utils::Environment).to receive(:in_container?).and_return(false)
      allow(File).to receive(:exist?).and_return(true)
      allow(app).to receive(:send_command).and_return({ success: true }.to_json)
      allow(JSON).to receive(:parse).and_call_original
    end

    context "when filename is empty but current notebook in session" do
      it "uses the filename from session" do
        session[:current_notebook_filename] = "session_notebook.ipynb"
        app.interrupt_jupyter_execution(filename: nil, session: session)
        expect(app).to have_received(:send_command).with(
          hash_including(command: include("session_notebook.ipynb"))
        )
      end
    end

    context "when filename is empty and no current notebook in session" do
      it "returns an error" do
        session[:current_notebook_filename] = nil
        result = app.interrupt_jupyter_execution(filename: nil, session: session)
        expect(result).to eq({ success: false, error: "Filename is required and cannot be empty (or current notebook not set in session)." })
      end
    end
  end

  describe "#move_jupyter_cell" do
    before do
      allow(Monadic::Utils::Environment).to receive(:in_container?).and_return(false)
      allow(File).to receive(:exist?).and_return(true)
      allow(app).to receive(:send_command).and_return({ success: true }.to_json)
      allow(JSON).to receive(:parse).and_call_original
    end

    context "when filename is empty but current notebook in session" do
      it "uses the filename from session" do
        session[:current_notebook_filename] = "session_notebook.ipynb"
        app.move_jupyter_cell(filename: nil, from_index: 0, to_index: 1, session: session)
        expect(app).to have_received(:send_command).with(
          hash_including(command: include("session_notebook.ipynb"))
        )
      end
    end

    context "when filename is empty and no current notebook in session" do
      it "returns an error" do
        session[:current_notebook_filename] = nil
        result = app.move_jupyter_cell(filename: nil, from_index: 0, to_index: 1, session: session)
        expect(result).to eq({ success: false, error: "Filename is required and cannot be empty (or current notebook not set in session)." })
      end
    end

    context "when indices are invalid" do
      it "returns an error for negative from_index" do
        result = app.move_jupyter_cell(filename: "notebook.ipynb", from_index: -1, to_index: 1, session: session)
        expect(result).to eq({ success: false, error: "From index must be a non-negative integer." })
      end

      it "returns an error for non-integer from_index" do
        result = app.move_jupyter_cell(filename: "notebook.ipynb", from_index: "abc", to_index: 1, session: session)
        expect(result).to eq({ success: false, error: "From index must be a non-negative integer." })
      end

      it "returns an error for negative to_index" do
        result = app.move_jupyter_cell(filename: "notebook.ipynb", from_index: 0, to_index: -1, session: session)
        expect(result).to eq({ success: false, error: "To index must be a non-negative integer." })
      end

      it "returns an error for non-integer to_index" do
        result = app.move_jupyter_cell(filename: "notebook.ipynb", from_index: 0, to_index: "abc", session: session)
        expect(result).to eq({ success: false, error: "To index must be a non-negative integer." })
      end
    end
  end

  describe "#insert_jupyter_cells" do
    before do
      allow(Monadic::Utils::Environment).to receive(:in_container?).and_return(false)
      allow(File).to receive(:exist?).and_return(true)
      allow(app).to receive(:send_command).and_return({ success: true }.to_json)
      allow(JSON).to receive(:parse).and_call_original
    end

    context "when filename is empty but current notebook in session" do
      it "uses the filename from session" do
        session[:current_notebook_filename] = "session_notebook.ipynb"
        valid_cells = [{ "cell_type" => "code", "source" => "print('hello')" }]
        app.insert_jupyter_cells(filename: nil, index: 0, cells: valid_cells, session: session)
        expect(app).to have_received(:send_command).with(
          hash_including(command: include("session_notebook.ipynb"))
        )
      end
    end

    context "when filename is empty and no current notebook in session" do
      it "returns an error" do
        session[:current_notebook_filename] = nil
        valid_cells = [{ "cell_type" => "code", "source" => "print('hello')" }]
        result = app.insert_jupyter_cells(filename: nil, index: 0, cells: valid_cells, session: session)
        expect(result).to eq({ success: false, error: "Filename is required and cannot be empty (or current notebook not set in session)." })
      end
    end

    context "when index is invalid" do
      it "returns an error for negative index" do
        valid_cells = [{ "cell_type" => "code", "source" => "print('hello')" }]
        result = app.insert_jupyter_cells(filename: "notebook.ipynb", index: -1, cells: valid_cells, session: session)
        expect(result).to eq({ success: false, error: "Index must be a non-negative integer." })
      end

      it "returns an error for non-integer index" do
        valid_cells = [{ "cell_type" => "code", "source" => "print('hello')" }]
        result = app.insert_jupyter_cells(filename: "notebook.ipynb", index: "abc", cells: valid_cells, session: session)
        expect(result).to eq({ success: false, error: "Index must be a non-negative integer." })
      end
    end

    context "when cells is invalid" do
      it "returns an error for non-array cells" do
        result = app.insert_jupyter_cells(filename: "notebook.ipynb", index: 0, cells: "not an array", session: session)
        expect(result).to eq({ success: false, error: "Cells must be an array." })
      end
    end
  end

  describe "#list_jupyter_notebooks" do
    before do
      allow(app).to receive(:super).with(hash_including(session: session)).and_return(["notebook1.ipynb", "notebook2.ipynb"])
    end

    it "calls the super method with the session and returns the list of notebooks" do
      result = app.list_jupyter_notebooks(session: session)
      expect(result).to eq(["notebook1.ipynb", "notebook2.ipynb"])
      expect(app).to have_received(:super).with(hash_including(session: session))
    end
  end

  describe "Japanese font setup" do
    it "includes Japanese font configuration constant" do
      expect(MonadicHelper::JAPANESE_FONT_SETUP).to include("Noto Sans CJK JP")
      expect(MonadicHelper::JAPANESE_FONT_SETUP).to include("matplotlib")
      expect(MonadicHelper::JAPANESE_FONT_SETUP).to include("font.sans-serif")
    end
  end
end