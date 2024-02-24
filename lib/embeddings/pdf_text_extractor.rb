# frozen_string_literal: false

require "poppler"
require "parallel"
require "tiktoken_ruby"

RAG_TOKENS = 4000
RAG_OVERLAP_LINES = 5

class PDF2Text
  THREADS = 4

  attr_reader :file_path, :text_data

  # Initializes the PDF2Text class
  def initialize(path:, max_tokens: RAG_TOKENS, separator: "\n", overwrap_lines: RAG_OVERLAP_LINES)
    @file_path = path
    @file_name = File.basename(path)
    @max_tokens = max_tokens
    @text_data = ""
    @separator = separator
    @overwrap_lines = overwrap_lines
  end

  # Extracts the text from the PDF file
  def extract
    doc = Poppler::Document.new(@file_path)
    @text_data = ""

    Parallel.each(0...doc.n_pages, in_threads: THREADS) do |page_num|
      page = doc.get_page(page_num)
      @text_data += "#{page.get_text}\n"
    end

    @text_data
  end

  # Splits the text into chunks of `max_tokens` tokens
  # if overwrap_lines is set, it will add the specified number of lines
  # to the next chunk
  def split_text
    encoder = Tiktoken.get_encoding("cl100k_base")
    lines = @text_data.split(@separator)
    split_texts = []
    current_text = []
    current_tokens = 0

    last_n_lines = []

    lines.each do |line|
      line_tokens = encoder.encode(line)
      line_token_count = line_tokens.size

      if current_tokens + line_token_count > @max_tokens
        split_texts << { "text" => current_text.join(@separator).strip, "tokens" => current_tokens }
        current_text = current_text.last(@overwrap_lines)
        current_tokens = encoder.encode(current_text.join(@separator)).size
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
    pdf = PDF2Text.new(path: file_path, max_tokens: RAG_TOKENS, separator: "\n", overwrap_lines: RAG_OVERLAP_LINES)
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
