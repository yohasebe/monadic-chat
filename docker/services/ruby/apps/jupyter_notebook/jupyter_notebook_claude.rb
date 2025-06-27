# frozen_string_literal: true

require_relative "../../lib/monadic/monadic_app"
require_relative "../../lib/monadic/helpers/monadic_helper"

# Jupyter Notebook app with Claude
class JupyterNotebookClaude < MonadicApp
  include MonadicHelper
  include ClaudeHelper
  
  def description
    # This is loaded from MDSL
  end
end