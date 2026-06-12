# frozen_string_literal: true

require 'json'
require 'open3'
require_relative 'importers'
require_relative '../utils/environment'
require_relative '../utils/degradation_notifier'
require_relative '../extractor/client'

module Monadic
  module Library
    # Extension-based dispatch over the file-oriented importers.
    #
    # The Library Browse modal's "Import file" button uploads a file via
    # POST /library/import; that route hands the file to FileImporter,
    # which:
    #   - selects the right importer based on extension
    #   - reads the file (Markdown / Code) directly OR runs the Python
    #     extractor (subprocess inside the python container, OR HTTP to
    #     the extractor_service container when the user has installed
    #     the Knowledge Base Quality Pack)
    #   - returns a monadic-conversation v1 hash ready for
    #     Manager.import_conversation
    #
    # PDF routing is two-tier:
    #   - When EXTRACTOR_SERVICE=true and the extractor_service container
    #     is reachable, PDFs go through Docling+RapidOCR for layout-aware
    #     extraction with OCR.
    #   - Otherwise, PDFs fall back to pdfplumber via the python
    #     container subprocess (fast, born-digital only, no OCR).
    #
    # This module is the single point of coupling between Ruby file
    # ingestion and the python/extractor containers. Unit specs stub
    # `run_python_extractor` and `extract_via_service` to keep tests
    # Docker-free.
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
        json_string = if extractor_service_available?
                        extract_via_service(path)
                      else
                        # Falling back to pdfplumber is normal when the user
                        # never installed the Quality Pack, but a degradation
                        # when they opted in and the service is down — say so
                        # instead of silently importing at lower quality.
                        if extractor_opted_in?
                          Monadic::Utils::DegradationNotifier.report(
                            component: "extractor",
                            message: "Knowledge Base Quality Pack is enabled but the extractor service is unreachable; importing #{filename} with the basic pdfplumber path (no OCR, no layout analysis).",
                            severity: :warning
                          )
                        end
                        run_python_extractor(PDF_EXTRACTOR, path)
                      end
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

      # Has the user opted in to the Quality Pack? Used to distinguish
      # "fallback because never installed" (normal) from "fallback because
      # the service is down" (degradation worth reporting).
      def extractor_opted_in?
        ENV['EXTRACTOR_SERVICE'].to_s.downcase == 'true'
      end

      # Gate: ENV opt-in + a cheap health probe so we degrade gracefully
      # the moment the container is stopped or uninstalled. The result is
      # NOT cached — health is fast (~ms when up) and stale state would
      # silently route imports to the wrong path.
      def extractor_service_available?
        return false unless extractor_opted_in?
        Monadic::Extractor::Client.new.health
      rescue StandardError
        false
      end

      # HTTP path: send the container-side path to extractor_service
      # /v1/extract and return a JSON string in the same shape that
      # Importers::Pdf.import_extraction_json expects (title, author,
      # page_count, markdown).
      def extract_via_service(path)
        container_path = host_path_to_container(path)
        client = Monadic::Extractor::Client.new
        response = client.extract(path: container_path, format: 'pdf')
        # Importers::Pdf only consumes title/author/page_count/markdown;
        # extractor_meta is preserved at the top level for callers that
        # want to inspect pipeline / duration but is ignored downstream.
        JSON.dump(response)
      rescue Monadic::Extractor::Client::ServiceUnavailableError,
             Monadic::Extractor::Client::ExtractionFailedError => e
        raise ExtractionError, "extractor_service: #{e.message}"
      end
    end
  end
end
