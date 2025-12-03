# frozen_string_literal: true

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
# - restart_jupyter_kernel: Restart kernel and clear outputs
# - interrupt_jupyter_execution: Interrupt running cells
# - move_jupyter_cell: Reorganize notebook structure
# - insert_jupyter_cells: Insert cells at specific positions
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

    # Create a new Jupyter notebook
    def create_jupyter_notebook(filename:, session: nil)
      unless filename && !filename.empty?
        return {
          success: false,
          error: "Filename is required and cannot be empty."
        }
      end

      # MonadicHelper#create_jupyter_notebook doesn't accept session parameter
      result = super(filename: filename)

      # Store the created notebook's filename in the session
      if session && result.is_a?(Hash) && result["success"]
        session[:current_notebook_filename] = filename
      end

      result
    end

    # Add and run cells in a Jupyter notebook
    def add_jupyter_cells(filename:, cells:, run: true, escaped: false, session: nil)
      # Use filename from session if not explicitly provided
      filename ||= session[:current_notebook_filename] if session

      unless filename && !filename.empty?
        return {
          success: false,
          error: "Filename is required and cannot be empty (or current notebook not set in session)."
        }
      end

      unless cells.is_a?(Array)
        return {
          success: false,
          error: "Cells must be an array."
        }
      end

      # MonadicHelper#add_jupyter_cells doesn't accept session parameter
      super(filename: filename, cells: cells, run: run, escaped: escaped)
    end

    # Delete a cell from a Jupyter notebook
    def delete_jupyter_cell(filename:, index:, session: nil)
      # Use filename from session if not explicitly provided
      filename ||= session[:current_notebook_filename] if session

      unless filename && !filename.empty?
        return {
          success: false,
          error: "Filename is required and cannot be empty (or current notebook not set in session)."
        }
      end

      unless index.is_a?(Integer) && index >= 0
        return {
          success: false,
          error: "Index must be a non-negative integer."
        }
      end

      # MonadicHelper#delete_jupyter_cell doesn't accept session parameter
      super(filename: filename, index: index)
    end

    # Update the content of a cell in a Jupyter notebook
    def update_jupyter_cell(filename:, index:, content:, cell_type: "code", session: nil)
      # Use filename from session if not explicitly provided
      filename ||= session[:current_notebook_filename] if session

      unless filename && !filename.empty?
        return {
          success: false,
          error: "Filename is required and cannot be empty (or current notebook not set in session)."
        }
      end

      unless index.is_a?(Integer) && index >= 0
        return {
          success: false,
          error: "Index must be a non-negative integer."
        }
      end

      unless content
        return {
          success: false,
          error: "Content is required."
        }
      end

      unless %w[code markdown].include?(cell_type)
        return {
          success: false,
          error: "Cell type must be 'code' or 'markdown'."
        }
      end

      # MonadicHelper#update_jupyter_cell doesn't accept session parameter
      super(filename: filename, index: index, content: content, cell_type: cell_type)
    end

    # Get all cells with their execution results, including error information
    def get_jupyter_cells_with_results(filename:, session: nil)
      # Use filename from session if not explicitly provided
      filename ||= session[:current_notebook_filename] if session

      unless filename && !filename.empty?
        return {
          success: false,
          error: "Filename is required and cannot be empty (or current notebook not set in session)."
        }
      end

      # MonadicHelper#get_jupyter_cells_with_results doesn't accept session parameter
      super(filename: filename)
    end

    # Execute cells and get error information for fixing
    def execute_and_fix_jupyter_cells(filename:, max_retries: 3, session: nil)
      # Use filename from session if not explicitly provided
      filename ||= session[:current_notebook_filename] if session

      unless filename && !filename.empty?
        return {
          success: false,
          error: "Filename is required and cannot be empty (or current notebook not set in session)."
        }
      end

      unless max_retries.is_a?(Integer) && max_retries > 0
        return {
          success: false,
          error: "Max retries must be a positive integer."
        }
      end

      # MonadicHelper#execute_and_fix_jupyter_cells doesn't accept session parameter
      super(filename: filename, max_retries: max_retries)
    end

    # List all Jupyter notebooks in the data directory
    def list_jupyter_notebooks(session: nil)
      # MonadicHelper#list_jupyter_notebooks doesn't accept session parameter
      super()
    end

    # Restart the kernel for a notebook and clear all outputs
    def restart_jupyter_kernel(filename:, session: nil)
      # Use filename from session if not explicitly provided
      filename ||= session[:current_notebook_filename] if session

      unless filename && !filename.empty?
        return {
          success: false,
          error: "Filename is required and cannot be empty (or current notebook not set in session)."
        }
      end

      # MonadicHelper#restart_jupyter_kernel doesn't accept session parameter
      super(filename: filename)
    end

    # Interrupt currently running cells
    def interrupt_jupyter_execution(filename:, session: nil)
      # Use filename from session if not explicitly provided
      filename ||= session[:current_notebook_filename] if session

      unless filename && !filename.empty?
        return {
          success: false,
          error: "Filename is required and cannot be empty (or current notebook not set in session)."
        }
      end

      # MonadicHelper#interrupt_jupyter_execution doesn't accept session parameter
      super(filename: filename)
    end

    # Move a cell to a new position in the notebook
    def move_jupyter_cell(filename:, from_index:, to_index:, session: nil)
      # Use filename from session if not explicitly provided
      filename ||= session[:current_notebook_filename] if session

      unless filename && !filename.empty?
        return {
          success: false,
          error: "Filename is required and cannot be empty (or current notebook not set in session)."
        }
      end

      unless from_index.is_a?(Integer) && from_index >= 0
        return {
          success: false,
          error: "From index must be a non-negative integer."
        }
      end

      unless to_index.is_a?(Integer) && to_index >= 0
        return {
          success: false,
          error: "To index must be a non-negative integer."
        }
      end

      # MonadicHelper#move_jupyter_cell doesn't accept session parameter
      super(filename: filename, from_index: from_index, to_index: to_index)
    end

    # Insert cells at a specific position in the notebook
    def insert_jupyter_cells(filename:, index:, cells:, run: false, session: nil)
      # Use filename from session if not explicitly provided
      filename ||= session[:current_notebook_filename] if session

      unless filename && !filename.empty?
        return {
          success: false,
          error: "Filename is required and cannot be empty (or current notebook not set in session)."
        }
      end

      unless index.is_a?(Integer) && index >= 0
        return {
          success: false,
          error: "Index must be a non-negative integer."
        }
      end

      unless cells.is_a?(Array)
        return {
          success: false,
          error: "Cells must be an array."
        }
      end

      # MonadicHelper#insert_jupyter_cells doesn't accept session parameter
      super(filename: filename, index: index, cells: cells, run: run)
    end
  end
end
