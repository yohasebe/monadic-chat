# frozen_string_literal: false

require "poppler"
require "parallel"
require "tiktoken_ruby"

class PDF2Text
  THREADS = 4

  attr_reader :file_path, :text_data

  # Initializes the PDF2Text class
  def initialize(file_path)
    @file_path = file_path
    @file_name = File.basename(file_path)
    @text_data = ""
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
  def split_text(max_tokens = 800)
    encoder = Tiktoken.get_encoding("cl100k_base")
    lines = @text_data.split("\n")
    split_texts = []
    current_text = ""
    current_tokens = 0

    Parallel.each(lines, in_threads: THREADS) do |line|
      line_tokens = encoder.encode(line)
      line_token_count = line_tokens.size

      if current_tokens + line_token_count > max_tokens
        split_texts << { "text" => current_text.strip, "tokens" => current_tokens }
        current_text = ""
        current_tokens = 0
      end

      current_text += "#{line}\n"
      current_tokens += line_token_count
    end

    # Add the remaining text if it's not empty
    #
    split_texts << { "text" => current_text.strip, "tokens" => current_tokens } unless current_text.strip.empty?
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
    pdf = PDF2Text.new(file_path)
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
