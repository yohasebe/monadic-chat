# frozen_string_literal: false

require "fileutils"
require "securerandom"
require_relative "debug_helper"
require_relative "shared_path_guard"

RAG_TOKENS = ENV.fetch("PDF_RAG_TOKENS", "4000").to_i
RAG_OVERLAP_LINES = ENV.fetch("PDF_RAG_OVERLAP_LINES", "4").to_i

class PDF2Text
  # As long as the extractor service is given (OCR over many pages).
  EXTRACT_TIMEOUT = 600 # seconds

  attr_reader :file_path, :text_data

  # Initializes the PDF2Text class. in_shared: whether path is a file of the
  # shared folder (read through SharedPathGuard, never through a link) or
  # the server's own file elsewhere (an upload's temporary file), which the
  # caller says, not where the path points.
  def initialize(path:, max_tokens: RAG_TOKENS, separator: "\n", overwrap_lines: RAG_OVERLAP_LINES, in_shared: true)
    @in_shared = in_shared
    @file_path = path
    @file_name = File.basename(path)
    @max_tokens = max_tokens
    @text_data = ""
    @separator = separator
    @overwrap_lines = overwrap_lines
  end

  def pdf2text(file_path)
    unless File.exist?(file_path)
      raise "PDF file not found"
    end

    data_path = Monadic::Utils::Environment.data_path + "/"

    # The python container reads the file through the shared folder. The copy
    # has a name of its own, so extractions at the same time do not read each
    # other's file, and it is removed when the extraction ends.
    new_file_name = "pdf2text_#{SecureRandom.hex(8)}.pdf"
    new_file_path = File.expand_path(File.join(data_path, new_file_name))

    guard = Monadic::Utils::SharedPathGuard
    if @in_shared
      guard.copy_file!(file_path, new_file_path, replace: false)
    else
      File.open(file_path, "rb") { |source| guard.write_file!(new_file_path, source, replace: false) }
    end
    # Only a copy this call put in place is removed afterwards.
    copied = new_file_path

    # Route through Monadic::Shell so the container name and the
    # shared-volume workdir share the same source of truth as every
    # other docker invocation.
    require_relative '../shell'
    body = "pdf2txt.py #{Monadic::Shell.escape(new_file_name)} --format md --json"
    stdout, stderr, status = Monadic::Shell.bash(container: :python, body: body, timeout: EXTRACT_TIMEOUT)
    if status.success?
      begin
        # Filter out any non-JSON content before the opening brace.
        # PDF backends can occasionally emit informational text to stdout;
        # we strip anything before the first '{' to keep JSON parsing robust.
        json_start = stdout.index("{")
        if json_start && json_start > 0
          DebugHelper.debug("Filtered #{json_start} bytes of non-JSON prefix from pdf2txt.py output", category: :app, level: :info) if defined?(CONFIG) && CONFIG["EXTRA_LOGGING"]
          stdout = stdout[json_start..]
        end
        JSON.parse(stdout)
      rescue JSON::ParserError => e
        DebugHelper.debug("Invalid JSON from pdf2txt.py: #{stdout[0..200]}", category: :app, level: :error)
        raise "PDF extraction returned invalid JSON format"
      end
    else
      raise "Error extracting text: #{stderr}"
    end
  ensure
    begin
      Monadic::Utils::SharedPathGuard.delete_file!(copied) if copied
    rescue Monadic::Utils::SharedPathGuard::InvalidPath, SystemCallError
      nil
    end
  end

  # Extracts the text from the PDF file
  def extract
    doc_json = pdf2text(@file_path)
    @text_data = ""

    begin
      pages = doc_json["pages"]
      raise "No pages found in PDF" if pages.nil? || pages.empty?
      
      # In page order.
      @text_data = pages.map do |page|
        text = page["text"].gsub(/[^[:print:]\s]/, " ")
        "#{text.encode('UTF-8', invalid: :replace, undef: :replace, replace: '')}\n"
      end.join
    rescue NoMethodError => e
      DebugHelper.debug("Invalid PDF structure: #{e.message}", category: :app, level: :error)
      raise "PDF file appears to be corrupted or empty"
    end

    @text_data
  end

  # Splits the text into chunks of `max_tokens` tokens
  # if overwrap_lines is set, it will add the specified number of lines
  # to the next chunk
  def split_text
    lines = @text_data.split(@separator)
    split_texts = []
    current_text = []
    current_tokens = 0

    lines.each do |line|
      line_tokens = MonadicApp::TOKENIZER.get_tokens_sequence(line)
      line_token_count = line_tokens.size

      if current_tokens + line_token_count > @max_tokens
        split_texts << { "text" => current_text.join(@separator).strip, "tokens" => current_tokens }
        current_text = current_text.last(@overwrap_lines)
        current_tokens = MonadicApp::TOKENIZER.get_tokens_sequence(current_text.join(@separator)).size
      end

      current_text << line.strip
      current_tokens += line_token_count
    end

    # Add the remaining text if it's not empty
    split_texts << { "text" => current_text.join(@separator).strip, "tokens" => current_tokens } unless current_text.empty?
    split_texts
  end
end

# If this file is run directly, it will extract the text from the PDF file given as argument
if $PROGRAM_NAME == __FILE__
  if ARGV.length != 1
    puts "Usage: ruby pdf_text_extractor.rb <pdf_file_path>"
    exit
  end

  file_path = ARGV[0]

  if File.exist?(file_path)
    pdf = PDF2Text.new(path: file_path, max_tokens: RAG_TOKENS, separator: "\n", overwrap_lines: RAG_OVERLAP_LINES, in_shared: false)
    pdf.extract
    split_texts = pdf.split_text
    split_texts.each_with_index do |split_text, index|
      puts "Section #{index + 1}:"
      puts split_text["text"]
      puts "Tokens: #{split_text["tokens"]}"
      puts "-----------------------------"
    end
  else
    puts "File not found: #{file_path}"
  end
end
