# frozen_string_literal: true

require 'json'
require_relative '../workspace/notebooks'
require_relative '../workspace/chats'
require_relative 'workbench_tools'

# JupyterOperations Shared Tools
#
# Provides core Jupyter Notebook operations for creating, managing, and executing
# notebooks across all AI providers.
#
# This module wraps MonadicHelper's Jupyter functionality to provide a consistent
# interface for all apps that need Jupyter notebook capabilities.
#
# Tools included:
# - run_jupyter: Start/stop JupyterLab server
# - create_jupyter_notebook: Create new notebooks
# - add_jupyter_cells: Add and execute cells
# - delete_jupyter_cell: Remove cells
# - update_jupyter_cell: Modify cell content
# - get_jupyter_cells_with_results: Retrieve cells with execution results
# - execute_and_fix_jupyter_cells: Execute with automatic error detection
# - list_jupyter_notebooks: List all notebooks
# - clear_jupyter_outputs: Clear the outputs a notebook keeps
# - move_jupyter_cell: Reorganize notebook structure
# - insert_jupyter_cells: Insert cells at specific positions
#
# Every run starts a new kernel and runs the whole notebook; the user stops
# a run with Cancel.
#
# A notebook a tool makes or changes is shown in the work screen for the
# reply (the result still gives its JupyterLab address).
#
# NOTE: Provider-specific optimization tools like `create_and_populate_jupyter_notebook`
# (used by Grok and Gemini for parallel function calling) are NOT included here.
# Those remain as individual tool definitions in their respective apps.

module MonadicSharedTools
  module JupyterOperations
    include MonadicHelper

    # Start or stop JupyterLab server
    def run_jupyter(command:, session: nil)
      unless %w[start stop].include?(command)
        return {
          success: false,
          error: "Invalid command. Must be 'start' or 'stop'."
        }
      end

      # MonadicHelper#run_jupyter doesn't accept session parameter
      super(command: command)
    end

    # Create a new Jupyter notebook: in the chat's folder (work/), or at the
    # top of the shared folder for a call with no chat.
    def create_jupyter_notebook(filename:, session: nil, workbench: nil)
      chat_id = notebook_chat(session, workbench)
      unless chat_id
        result = super(filename: filename)
        return shown_with(result, created_notebook(result), workbench)
      end

      path, result = notebook_made(chat_id, filename, session)
      shown_with(result, path, workbench)
    end

    # Add and run cells in a Jupyter notebook
    def add_jupyter_cells(filename:, cells:, run: true, escaped: false, session: nil, workbench: nil)
      filename, refused = notebook_for(filename, session, workbench)
      return refused if refused

      # MonadicHelper#add_jupyter_cells doesn't accept session parameter
      result = super(filename: filename, cells: cells, run: run, escaped: escaped)

      # Store the notebook URL in session so report_verification can reference it
      if session && result.is_a?(String) && result =~ /Access the notebook at:\s*(http\S+)/
        session[:last_notebook_url] = $1
      end

      shown_with(result, filename, workbench)
    end

    # Delete a cell from a Jupyter notebook
    def delete_jupyter_cell(filename:, index:, session: nil, workbench: nil)
      filename, refused = notebook_for(filename, session, workbench)
      return refused if refused

      shown_with(super(filename: filename, index: index), filename, workbench)
    end

    # Update the content of a cell in a Jupyter notebook
    def update_jupyter_cell(filename:, index:, content:, cell_type: "code", session: nil, workbench: nil)
      filename, refused = notebook_for(filename, session, workbench)
      return refused if refused
      return "Error: Cell type must be 'code' or 'markdown'." unless %w[code markdown].include?(cell_type)

      shown_with(super(filename: filename, index: index, content: content, cell_type: cell_type), filename, workbench)
    end

    # Get all cells with their execution results, including error information
    def get_jupyter_cells_with_results(filename:, session: nil, workbench: nil)
      filename, refused = notebook_for(filename, session, workbench)
      return refused if refused

      super(filename: filename)
    end

    # Execute cells and get error information for fixing
    def execute_and_fix_jupyter_cells(filename:, max_retries: 3, session: nil, workbench: nil)
      filename, refused = notebook_for(filename, session, workbench)
      return refused if refused

      shown_with(super(filename: filename, max_retries: max_retries), filename, workbench)
    end

    # The chat's notebooks, or those at the top of the shared folder for a
    # call with no chat.
    def list_jupyter_notebooks(session: nil, workbench: nil)
      chat_id = notebook_chat(session, workbench)
      return super() unless chat_id

      known = Monadic::Workspace::Notebooks.known(chat_id)
      return "This chat has no notebooks yet." if known.empty?

      known.map { |path| "- #{Monadic::Workspace::Notebooks.named(path)}" }.join("\n")
    end

    # Clear the outputs a notebook keeps
    def clear_jupyter_outputs(filename:, session: nil, workbench: nil)
      filename, refused = notebook_for(filename, session, workbench)
      return refused if refused

      shown_with(super(filename: filename), filename, workbench)
    end

    # Move a cell to a new position in the notebook
    def move_jupyter_cell(filename:, from_index:, to_index:, session: nil, workbench: nil)
      filename, refused = notebook_for(filename, session, workbench)
      return refused if refused

      shown_with(super(filename: filename, from_index: from_index, to_index: to_index), filename, workbench)
    end

    # Insert cells at a specific position in the notebook
    def insert_jupyter_cells(filename:, index:, cells:, run: false, session: nil, workbench: nil)
      filename, refused = notebook_for(filename, session, workbench)
      return refused if refused

      shown_with(super(filename: filename, index: index, cells: cells, run: run), filename, workbench)
    end

    # Made and filled in one call (the tool some providers are given).
    def create_and_populate_jupyter_notebook(filename:, cells: [], run: true, session: nil, workbench: nil)
      chat_id = notebook_chat(session, workbench)
      unless chat_id
        result = super(filename: filename, cells: cells, run: run)
        return shown_with(result, created_notebook(result), workbench)
      end

      path, created = notebook_made(chat_id, filename, session)
      return created unless path
      return shown_with(created, path, workbench) unless cells.is_a?(Array) && !cells.empty?

      "#{created}\n\n#{add_jupyter_cells(filename: path, cells: cells, run: run, session: session, workbench: workbench)}"
    end

    private

    # The chat a notebook call is for: the one the reply was asked in, or
    # the session's; nil for a call with no chat (an MCP call).
    def notebook_chat(session, workbench)
      chat_id = workbench&.chat_id || (session && session[Monadic::Workspace::Chats::SESSION_KEY])
      Monadic::Workspace::Ids.valid?(:chat, chat_id) ? chat_id : nil
    end

    # [path, nil] for the chat's notebook the name stands for (the one used
    # last, or else the latest, for no name), or [nil, what was refused].
    # With no chat, the name as given.
    def notebook_for(filename, session, workbench)
      chat_id = notebook_chat(session, workbench)
      unless chat_id
        return [nil, "Error: Filename is required."] if filename.to_s.strip.empty?

        return [filename, nil]
      end

      notebooks = Monadic::Workspace::Notebooks
      current = session && session[:current_notebook_filename]
      current = notebooks.known(chat_id).first if current.to_s.empty?
      path = notebooks.resolve(chat_id, filename, current: current)
      remember_notebook(path, session)
      [path, nil]
    rescue Monadic::Workspace::Notebooks::Refused => e
      [nil, "Error: #{e.message}"]
    end

    # [path, what the tool says] for a new notebook in the chat's folder, or
    # [nil, what was refused].
    def notebook_made(chat_id, filename, session)
      path = Monadic::Workspace::Notebooks.create(chat_id, app_name: notebook_app(session), name: filename)
      remember_notebook(path, session)
      [path, "Notebook #{path} created successfully. Access it at: #{get_jupyter_notebook_url(path)}"]
    rescue Monadic::Workspace::Notebooks::Refused => e
      [nil, "Error: #{e.message}"]
    end

    # The notebook used last: the default for the next call, and what the
    # app's state names (the ${NOTEBOOK} vocabulary reads it).
    def remember_notebook(path, session)
      return unless session

      session[:current_notebook_filename] = path
      return unless respond_to?(:monadic_save_state)

      app = notebook_app(session)
      saved = JSON.parse(monadic_load_state(app: app, key: "context", session: session)).dig("data") rescue nil
      data = (saved.is_a?(Hash) ? saved : {}).merge("notebook_filename" => path)
      monadic_save_state(app: app, key: "context", payload: data, session: session)
    rescue StandardError => e
      Monadic::Utils::ExtraLogger.log { "[Jupyter] Notebook not remembered in the app state: #{e.class}" }
    end

    def notebook_app(session)
      (session && session.dig(:parameters, "app_name")) || self.class.name
    end

    # The notebook a creation made, as its result names it, or nil.
    def created_notebook(result)
      result.is_a?(String) ? result[/\ANotebook (.+?\.ipynb) created successfully/, 1] : nil
    end

    # The tool's result, once the notebook is shown in the work screen for
    # the reply; as it was when it cannot be (no reply to show it for, no
    # such file, a full work screen).
    def shown_with(result, filename, workbench)
      return result unless workbench && result.is_a?(String) && filename && !filename.to_s.empty?

      name = filename.to_s.end_with?(".ipynb") ? filename.to_s : "#{filename}.ipynb"
      said = WorkbenchTools.show_file(name, workbench)
      said.start_with?("{") ? "#{result}\n\nThe notebook is shown in the work screen beside the chat." : result
    end
  end
end
