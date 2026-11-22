# frozen_string_literal: true

require 'erb'
require_relative '../shell'
require_relative '../workspace/shared_folder'

module Monadic
  module Utils
    # JupyterLab in the Python container: its address on this machine, the
    # address of a notebook in it, and starting it when the user opens a
    # notebook (run_jupyter.sh starts one server at a time and waits until
    # it answers). Nothing else starts it.
    module JupyterLab
      # Published on this machine only.
      HOST = '127.0.0.1'
      # Longer than run_jupyter.sh waits (its lock, then the server's
      # answer): the script gives up first, so a server another request
      # started is never stopped because this one ran out of time.
      START_LIMIT = 120
      PATH_MAX = 1024

      module_function

      def base_url
        port = (defined?(CONFIG) && CONFIG['JUPYTER_PORT']) || ENV['JUPYTER_PORT'] || '8889'
        "http://#{HOST}:#{port}"
      end

      def notebook_url(path)
        "#{base_url}/lab/tree/#{path.split('/').map { |part| ERB::Util.url_encode(part) }.join('/')}"
      end

      # The path when it names a notebook file of the shared folder, reached
      # without a link and spelled as the folder lists it; nil otherwise.
      def notebook_path(value)
        text = value.to_s
        return nil if text.empty? || text.length > PATH_MAX || !text.downcase.end_with?('.ipynb')

        item = Monadic::Workspace::SharedFolder.entry(text)
        item && item[:kind] == 'file' ? text : nil
      rescue Monadic::Workspace::SharedFolder::Invalid
        nil
      end

      # Starts JupyterLab unless it answers: true once it answers.
      def start
        out, _err, status = Monadic::Shell.exec(container: :python, argv: %w[run_jupyter.sh run], timeout: START_LIMIT)
        status.success? && out.include?('JupyterLab is running')
      rescue StandardError
        false
      end
    end
  end
end
