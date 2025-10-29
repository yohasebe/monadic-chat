# frozen_string_literal: true

# Shared File Reading Tools for Monadic Chat
# Provides text extraction from various file formats
#
# This module bridges existing MonadicHelper methods for file content extraction.
# All implementations delegate to read_write_helper.rb for consistency.
#
# Usage in MDSL:
#   tools do
#     import_shared_tools :file_reading, visibility: "always"
#   end
#
# Available tools:
#   - fetch_text_from_file: Read text from regular files (txt, code, data, etc.)
#   - fetch_text_from_pdf: Extract text from PDF documents
#   - fetch_text_from_office: Extract text from Office files (docx, xlsx, pptx)

module MonadicSharedTools
  module FileReading
    include MonadicHelper

    # Read text content from a regular file
    #
    # Supports various text-based formats including:
    # - Plain text (.txt, .md, .csv, .json, etc.)
    # - Source code (.py, .rb, .js, .java, etc.)
    # - Data files (.xml, .yaml, .log, etc.)
    #
    # Delegates to MonadicHelper#fetch_text_from_file which:
    # - Validates file path for security
    # - Reads file via Ruby container
    # - Returns full text content with error handling
    #
    # @param file [String] Filename or path relative to shared folder
    # @return [String] File content or error message
    #
    # @example Read a text file
    #   fetch_text_from_file(file: "notes.txt")
    #
    # @example Read a Python script
    #   fetch_text_from_file(file: "scripts/analyzer.py")
    #
    # @example Read JSON data
    #   fetch_text_from_file(file: "data/config.json")
    def fetch_text_from_file(file:)
      # Validate input
      unless file
        return {
          success: false,
          error: "File parameter is required"
        }
      end

      if file.to_s.strip.empty?
        return {
          success: false,
          error: "File parameter cannot be empty"
        }
      end

      # Call existing MonadicHelper implementation
      # Returns string with content or error message
      super(file: file)
    end

    # Extract text content from a PDF file
    #
    # Uses Python's pdf2txt.py with markdown formatting and full-page support.
    # Automatically handles multi-page PDFs and preserves text structure.
    #
    # Delegates to MonadicHelper#fetch_text_from_pdf which:
    # - Validates file path for security
    # - Extracts text via Python container (pdfminer.six)
    # - Formats output as markdown
    # - Processes all pages automatically
    #
    # @param file [String] Filename of PDF document (parameter normalized from legacy 'pdf')
    # @return [String] Extracted text or error message
    #
    # @example Extract from PDF
    #   fetch_text_from_pdf(file: "reports/annual_report.pdf")
    #
    # @example Multi-page document
    #   fetch_text_from_pdf(file: "documents/whitepaper.pdf")
    #
    # Note: Parameter name normalized to 'file' for consistency across all file reading tools
    def fetch_text_from_pdf(file:)
      # Validate input
      unless file
        return {
          success: false,
          error: "File parameter is required"
        }
      end

      if file.to_s.strip.empty?
        return {
          success: false,
          error: "File parameter cannot be empty"
        }
      end

      # Call existing MonadicHelper implementation
      # Legacy method uses 'pdf' parameter, so we map 'file' → 'pdf'
      super(pdf: file)
    end

    # Extract text content from Microsoft Office files
    #
    # Supports:
    # - Word documents (.docx)
    # - Excel spreadsheets (.xlsx)
    # - PowerPoint presentations (.pptx)
    #
    # Delegates to MonadicHelper#fetch_text_from_office which:
    # - Validates file path for security
    # - Extracts text via Python container (python-docx, openpyxl, python-pptx)
    # - Returns formatted text content
    # - Handles tables, text boxes, and slide notes
    #
    # @param file [String] Filename of Office document
    # @return [String] Extracted text or error message
    #
    # @example Extract from Word document
    #   fetch_text_from_office(file: "contracts/agreement.docx")
    #
    # @example Extract from Excel spreadsheet
    #   fetch_text_from_office(file: "data/sales_report.xlsx")
    #
    # @example Extract from PowerPoint
    #   fetch_text_from_office(file: "presentations/pitch_deck.pptx")
    def fetch_text_from_office(file:)
      # Validate input
      unless file
        return {
          success: false,
          error: "File parameter is required"
        }
      end

      if file.to_s.strip.empty?
        return {
          success: false,
          error: "File parameter cannot be empty"
        }
      end

      # Call existing MonadicHelper implementation
      super(file: file)
    end
  end
end
