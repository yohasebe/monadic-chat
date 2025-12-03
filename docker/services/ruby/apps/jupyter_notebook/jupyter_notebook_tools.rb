# Facade methods for Jupyter Notebook apps
# All Jupyter functionality is already included in MonadicHelper module

require_relative '../../lib/monadic/agents/openai_code_agent'
require_relative '../../lib/monadic/agents/grok_code_agent'
require_relative '../../lib/monadic/shared_tools/monadic_session_state'

module JupyterNotebookTools
  include MonadicHelper
  include MonadicSharedTools::FileOperations
  include Monadic::Agents::OpenAICodeAgent

  # Call GPT-5-Codex agent for complex notebook code generation
  def openai_code_agent(task:, notebook_context: nil, cell_content: nil)
    # Build prompt using the shared helper
    prompt = build_openai_code_prompt(
      task: task,
      context: notebook_context,
      current_code: cell_content
    )

    # Call the shared GPT-5-Codex implementation
    call_openai_code(prompt: prompt, app_name: "JupyterNotebook")
  end
end

# Load JupyterOperations shared tools
require_relative '../../lib/monadic/shared_tools/jupyter_operations'

module JupyterNotebookGrokTools
  include MonadicHelper
  include MonadicSharedTools::FileOperations
  include Monadic::Agents::GrokCodeAgent

  # Call Grok-Code agent for complex notebook code generation
  def grok_code_agent(task:, notebook_context: nil, cell_content: nil)
    # Build prompt using the shared helper
    prompt = build_grok_code_prompt(
      task: task,
      context: notebook_context,
      current_code: cell_content
    )

    # Call the shared Grok-Code implementation
    call_grok_code(prompt: prompt, app_name: "JupyterNotebookGrok")
  end
end

class JupyterNotebookOpenAI < MonadicApp
  include OpenAIHelper if defined?(OpenAIHelper)
  include JupyterNotebookTools
  include MonadicSharedTools::JupyterOperations
  include Monadic::SharedTools::MonadicSessionState if defined?(Monadic::SharedTools::MonadicSessionState)
  # All methods are inherited from MonadicApp which includes MonadicHelper
  # JupyterOperations provides session-aware wrappers for Jupyter methods
  # MonadicSessionState provides monadic_load_state and monadic_save_state for context persistence

  # Override run_jupyter to auto-save state
  def run_jupyter(command:, session: nil)
    # JupyterOperations accepts session but doesn't pass it to MonadicHelper
    result = super(command: command, session: session)

    # Auto-save jupyter_running state
    if session && respond_to?(:monadic_save_state)
      begin
        app_key = session.dig(:parameters, "app_name") || "JupyterNotebookOpenAI"
        jupyter_running = (command == "start")

        # Load existing context and update
        existing = monadic_load_state(app: app_key, key: "context", session: session)
        existing_data = JSON.parse(existing).dig("data") || {} rescue {}

        new_context = existing_data.merge({
          "jupyter_running" => jupyter_running
        })

        monadic_save_state(app: app_key, key: "context", payload: new_context, session: session)
      rescue => e
        # Ignore state saving errors
      end
    end

    result
  end

  # Override create_jupyter_notebook to auto-save state
  def create_jupyter_notebook(filename:, session: nil)
    # JupyterOperations accepts session but doesn't pass it to MonadicHelper
    result = super(filename: filename, session: session)

    # Auto-save notebook context
    # Note: create_jupyter_notebook returns a string, not a hash, so check for success differently
    success = result.is_a?(String) && result.include?("successfully")
    if session && respond_to?(:monadic_save_state) && success
      begin
        app_key = session.dig(:parameters, "app_name") || "JupyterNotebookOpenAI"

        # Extract actual filename with timestamp from the result string
        # Format: "Notebook example_20241101_120000.ipynb created successfully..."
        actual_filename = if result =~ /Notebook\s+(\S+\.ipynb)/
                            $1
                          else
                            filename.to_s.end_with?(".ipynb") ? filename : "#{filename}.ipynb"
                          end

        # Load existing context and update
        existing = monadic_load_state(app: app_key, key: "context", session: session)
        existing_data = JSON.parse(existing).dig("data") || {} rescue {}

        new_context = existing_data.merge({
          "jupyter_running" => true,
          "notebook_created" => true,
          "notebook_filename" => actual_filename,
          "link" => "<a href='http://localhost:8889/lab/tree/#{actual_filename}' target='_blank'>#{actual_filename}</a>"
        })

        monadic_save_state(app: app_key, key: "context", payload: new_context, session: session)
      rescue => e
        # Ignore state saving errors
      end
    end

    result
  end
end

class JupyterNotebookClaude < MonadicApp
  include ClaudeHelper if defined?(ClaudeHelper)
  include MonadicHelper
  include MonadicSharedTools::FileOperations
  include MonadicSharedTools::JupyterOperations
  include Monadic::SharedTools::MonadicSessionState if defined?(Monadic::SharedTools::MonadicSessionState)
  # All methods are inherited from MonadicApp which includes MonadicHelper
  # JupyterOperations provides session-aware wrappers for Jupyter methods
  # MonadicSessionState provides monadic_load_state and monadic_save_state for context persistence

  # Override run_jupyter to auto-save state
  def run_jupyter(command:, session: nil)
    result = super(command: command, session: session)

    if session && respond_to?(:monadic_save_state)
      begin
        app_key = session.dig(:parameters, "app_name") || "JupyterNotebookClaude"
        jupyter_running = (command == "start")

        existing = monadic_load_state(app: app_key, key: "context", session: session)
        existing_data = JSON.parse(existing).dig("data") || {} rescue {}

        new_context = existing_data.merge({
          "jupyter_running" => jupyter_running
        })

        monadic_save_state(app: app_key, key: "context", payload: new_context, session: session)
      rescue => e
        # Ignore state saving errors
      end
    end

    result
  end

  # Override create_jupyter_notebook to auto-save state
  def create_jupyter_notebook(filename:, session: nil)
    result = super(filename: filename, session: session)

    success = result.is_a?(String) && result.include?("successfully")
    if session && respond_to?(:monadic_save_state) && success
      begin
        app_key = session.dig(:parameters, "app_name") || "JupyterNotebookClaude"

        actual_filename = if result =~ /Notebook\s+(\S+\.ipynb)/
                            $1
                          else
                            filename.to_s.end_with?(".ipynb") ? filename : "#{filename}.ipynb"
                          end

        existing = monadic_load_state(app: app_key, key: "context", session: session)
        existing_data = JSON.parse(existing).dig("data") || {} rescue {}

        new_context = existing_data.merge({
          "jupyter_running" => true,
          "notebook_created" => true,
          "notebook_filename" => actual_filename,
          "link" => "<a href='http://localhost:8889/lab/tree/#{actual_filename}' target='_blank'>#{actual_filename}</a>"
        })

        monadic_save_state(app: app_key, key: "context", payload: new_context, session: session)
      rescue => e
        # Ignore state saving errors
      end
    end

    result
  end
end

class JupyterNotebookGemini < MonadicApp
  include GeminiHelper if defined?(GeminiHelper)
  include MonadicHelper
  include MonadicSharedTools::FileOperations
  include MonadicSharedTools::JupyterOperations
  include Monadic::SharedTools::MonadicSessionState if defined?(Monadic::SharedTools::MonadicSessionState)
  # All methods are inherited from MonadicApp which includes MonadicHelper
  # JupyterOperations provides session-aware wrappers for Jupyter methods
  # MonadicSessionState provides monadic_load_state and monadic_save_state for context persistence

  # Override run_jupyter to auto-save state
  def run_jupyter(command:, session: nil)
    result = super(command: command, session: session)

    if session && respond_to?(:monadic_save_state)
      begin
        app_key = session.dig(:parameters, "app_name") || "JupyterNotebookGemini"
        jupyter_running = (command == "start")

        existing = monadic_load_state(app: app_key, key: "context", session: session)
        existing_data = JSON.parse(existing).dig("data") || {} rescue {}

        new_context = existing_data.merge({
          "jupyter_running" => jupyter_running
        })

        monadic_save_state(app: app_key, key: "context", payload: new_context, session: session)
      rescue => e
        # Ignore state saving errors
      end
    end

    result
  end

  # Override create_jupyter_notebook to auto-save state
  def create_jupyter_notebook(filename:, session: nil)
    result = super(filename: filename, session: session)

    success = result.is_a?(String) && result.include?("successfully")
    if session && respond_to?(:monadic_save_state) && success
      begin
        app_key = session.dig(:parameters, "app_name") || "JupyterNotebookGemini"

        actual_filename = if result =~ /Notebook\s+(\S+\.ipynb)/
                            $1
                          else
                            filename.to_s.end_with?(".ipynb") ? filename : "#{filename}.ipynb"
                          end

        existing = monadic_load_state(app: app_key, key: "context", session: session)
        existing_data = JSON.parse(existing).dig("data") || {} rescue {}

        new_context = existing_data.merge({
          "jupyter_running" => true,
          "notebook_created" => true,
          "notebook_filename" => actual_filename,
          "link" => "<a href='http://localhost:8889/lab/tree/#{actual_filename}' target='_blank'>#{actual_filename}</a>"
        })

        monadic_save_state(app: app_key, key: "context", payload: new_context, session: session)
      rescue => e
        # Ignore state saving errors
      end
    end

    result
  end
end

class JupyterNotebookGrok < MonadicApp
  include GrokHelper if defined?(GrokHelper)
  include JupyterNotebookGrokTools
  include MonadicSharedTools::JupyterOperations
  include Monadic::SharedTools::MonadicSessionState if defined?(Monadic::SharedTools::MonadicSessionState)
  # All methods are inherited from MonadicApp which includes MonadicHelper
  # JupyterOperations provides session-aware wrappers for Jupyter methods
  # MonadicSessionState provides monadic_load_state and monadic_save_state for context persistence
  # Now includes Grok-Code agent support

  # Override run_jupyter to auto-save state
  def run_jupyter(command:, session: nil)
    result = super(command: command, session: session)

    if session && respond_to?(:monadic_save_state)
      begin
        app_key = session.dig(:parameters, "app_name") || "JupyterNotebookGrok"
        jupyter_running = (command == "start")

        existing = monadic_load_state(app: app_key, key: "context", session: session)
        existing_data = JSON.parse(existing).dig("data") || {} rescue {}

        new_context = existing_data.merge({
          "jupyter_running" => jupyter_running
        })

        monadic_save_state(app: app_key, key: "context", payload: new_context, session: session)
      rescue => e
        # Ignore state saving errors
      end
    end

    result
  end

  # Override create_jupyter_notebook to auto-save state
  def create_jupyter_notebook(filename:, session: nil)
    result = super(filename: filename, session: session)

    success = result.is_a?(String) && result.include?("successfully")
    if session && respond_to?(:monadic_save_state) && success
      begin
        app_key = session.dig(:parameters, "app_name") || "JupyterNotebookGrok"

        actual_filename = if result =~ /Notebook\s+(\S+\.ipynb)/
                            $1
                          else
                            filename.to_s.end_with?(".ipynb") ? filename : "#{filename}.ipynb"
                          end

        existing = monadic_load_state(app: app_key, key: "context", session: session)
        existing_data = JSON.parse(existing).dig("data") || {} rescue {}

        new_context = existing_data.merge({
          "jupyter_running" => true,
          "notebook_created" => true,
          "notebook_filename" => actual_filename,
          "link" => "<a href='http://localhost:8889/lab/tree/#{actual_filename}' target='_blank'>#{actual_filename}</a>"
        })

        monadic_save_state(app: app_key, key: "context", payload: new_context, session: session)
      rescue => e
        # Ignore state saving errors
      end
    end

    result
  end
end

# Shared utilities for Jupyter Notebook apps
module JupyterNotebookShared
  private
  
  def validate_notebook_input(code)
    raise ArgumentError, "Code cannot be empty" if code.to_s.strip.empty?
    true
  end
end