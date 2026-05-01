# frozen_string_literal: true

require 'json'
require 'open3'
require_relative 'importers'
require_relative '../utils/environment'

module Monadic
  module Library
    # Extension-based dispatch over the file-oriented importers.
    #
    # The Library Browse modal's "Import file" button uploads a file via
    # POST /library/import; that route hands the file to FileImporter,
    # which:
    #   - selects the right importer based on extension
    #   - reads the file (Markdown / Code) directly OR runs the Python
    #     extractor inside the python container (PDF / Office)
    #   - returns a monadic-conversation v1 hash ready for
    #     Manager.import_conversation
    #
    # This module is the single point of coupling between Ruby file
    # ingestion and the python container. Unit specs stub
    # `run_python_extractor` to keep tests Docker-free.
    module FileImporter
      module_function

      PYTHON_CONTAINER = 'monadic-chat-python-container'
      PDF_EXTRACTOR = '/monadic/scripts/utilities/library_pdf_extractor.py'
      OFFICE_EXTRACTOR = '/monadic/scripts/utilities/library_office_extractor.py'

      MARKDOWN_EXTS = %w[md markdown mdx].freeze
      OFFICE_EXTS = %w[docx xlsx pptx].freeze
      PDF_EXTS = %w[pdf].freeze

      class UnsupportedFormatError < ArgumentError; end
      class ExtractionError < StandardError; end

      # @param path [String] absolute path to the local file (host side)
      # @param filename [String, nil] display name; defaults to basename(path)
      # @param options [Hash] forwarded to the underlying importer
      # @return [Hash] monadic-conversation v1 hash
      def build_conversation(path:, filename: nil, options: {})
        filename ||= File.basename(path)
        ext = File.extname(filename).delete_prefix('.').downcase

        case
        when MARKDOWN_EXTS.include?(ext)
          import_markdown(path, filename, options)
        when PDF_EXTS.include?(ext)
          import_pdf(path, filename, options)
        when OFFICE_EXTS.include?(ext)
          import_office(path, filename, options)
        when code_extension?(ext, filename)
          import_code(path, filename, options)
        else
          raise UnsupportedFormatError,
                "Unsupported file extension: #{ext.empty? ? '(none)' : '.' + ext}"
        end
      end

      # Convenience: returns a flat list of recognised extensions for the
      # UI's accept attribute.
      def supported_extensions
        (MARKDOWN_EXTS + PDF_EXTS + OFFICE_EXTS + Importers::Code::EXTENSION_LANGUAGE.keys).map { |e| ".#{e}" }.uniq
      end

      # ─── Internals ─────────────────────────────────────────────────────

      def code_extension?(ext, filename)
        return true if Importers::Code::EXTENSION_LANGUAGE.key?(ext)
        # Filename-based detection (Rakefile / Gemfile / etc.). Reuse the
        # importer's own heuristic so we don't duplicate the table.
        Importers::Code.detect_language(filename) ? true : false
      end

      def import_markdown(path, filename, options)
        content = File.read(path, mode: 'rb').force_encoding('UTF-8')
        Importers::Markdown.import(content, options.merge(filename: filename))
      end

      def import_code(path, filename, options)
        content = File.read(path, mode: 'rb').force_encoding('UTF-8')
        Importers::Code.import(content, options.merge(filename: filename))
      end

      def import_pdf(path, filename, options)
        json_string = run_python_extractor(PDF_EXTRACTOR, path)
        Importers::Pdf.import_extraction_json(json_string, options.merge(filename: filename))
      end

      def import_office(path, filename, options)
        json_string = run_python_extractor(OFFICE_EXTRACTOR, path)
        Importers::Office.import_extraction_json(json_string, options.merge(filename: filename))
      end

      # Run a Python extractor in the python container against a host
      # path. Translates the host path into the container's view of the
      # shared volume (`/monadic/data`) before invoking docker exec.
      # Returns stdout (a single JSON line). Raises ExtractionError on
      # non-zero exit.
      def run_python_extractor(script_path, file_path)
        container_path = host_path_to_container(file_path)
        cmd = ['docker', 'exec', PYTHON_CONTAINER,
               'python', script_path, container_path]
        stdout, stderr, status = Open3.capture3(*cmd)
        unless status.success?
          raise ExtractionError, "extractor failed: #{stderr.strip}"
        end
        stdout
      end

      def host_path_to_container(path)
        host_root = Monadic::Utils::Environment.shared_volume
        return path unless path.start_with?(host_root)
        path.sub(host_root, '/monadic/data')
      end
    end
  end
end
