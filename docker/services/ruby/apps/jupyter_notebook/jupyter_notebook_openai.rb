# frozen_string_literal: true

require_relative "../../lib/monadic/monadic_app"
require_relative "../../lib/monadic/helpers/monadic_helper"

# Jupyter Notebook app with OpenAI
class JupyterNotebookOpenAI < MonadicApp
  include MonadicHelper
  include OpenAIHelper
  
  def description
    # This is loaded from MDSL
  end
end