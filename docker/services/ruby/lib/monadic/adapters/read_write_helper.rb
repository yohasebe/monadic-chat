require 'shellwords'
require_relative '../utils/shared_path_guard'

# Path validation helper for read/write operations

module MonadicHelper
  # Keep validation and execution on the same canonical path.
  def validate_file_path(file_path)
    Monadic::Utils::SharedPathGuard.resolve_in_shared(file_path, must_exist: false)
  end

  # The script each document reader runs, and the container it runs in.
  DOCUMENT_READERS = {
    "fetch_text_from_office" => { script: "office2txt.py", container: "python" },
    "fetch_text_from_pdf" => { script: "pdf2txt.py", container: "python", options: %w[--format md --all-pages] },
    "fetch_text_from_file" => { script: "content_fetcher.rb", container: "ruby" }
  }.freeze

  def fetch_text_from_office(file: "")
    read_document("fetch_text_from_office", file)
  end

  def fetch_text_from_pdf(pdf: "")
    read_document("fetch_text_from_pdf", pdf)
  end

  def fetch_text_from_file(file: "")
    read_document("fetch_text_from_file", file)
  end

  def read_document(tool, file)
    reader = DOCUMENT_READERS.fetch(tool)
    fetch_shared_document(file, reader[:script], reader[:container], *Array(reader[:options]))
  end

  def fetch_shared_document(file, script, container, *options)
    path = Monadic::Utils::SharedPathGuard.command_path(file, container: container)
    return "Error: Invalid file path or file not found" unless path

    command = Shellwords.join([script, path, *options])
    send_command(command: command, container: container) do |stdout, _stderr, status|
      # Some converters report errors on stdout, including with exit status 0.
      # Do not let send_command discard that failure or return an empty error.
      output = stdout.to_s
      converter_error = script != "content_fetcher.rb" && output.match?(/\A\s*(?:error[: ]|PDF file not found:|The specified file could not be found:|No such file or directory)/i)
      if !status.success? || converter_error
        "Error: Unable to read or convert the requested file"
      elsif output.strip.empty?
        "Error: The file is empty or contains no readable text"
      else
        respond_to?(:truncate_output, true) ? truncate_output(output) : output
      end
    end
  end
  private :fetch_shared_document
end
