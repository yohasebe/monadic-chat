# frozen_string_literal: false

require "parallel"

RAG_TOKENS = 2000
RAG_OVERLAP_LINES = 2

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

  def pdf2text(file_path)
    unless File.exist?(file_path)
      raise "PDF file not found"
    end

    data_path = if IN_CONTAINER
                  "/monadic/data/"
                else
                  "~/monadic/data/"
                end

    new_file_name = "#{Time.now.to_i}.pdf"
    new_file_path = File.expand_path(File.join(data_path, new_file_name))

    FileUtils.cp(file_path, new_file_path)
    shared_volume = "/monadic/data/"
    container = "monadic-chat-python-container"
    command = <<~CMD
      bash -c '/monadic/scripts/pdf2txt.py "#{new_file_name}" --format text'
    CMD
    docker_command = <<~DOCKER
      docker exec -w #{shared_volume} #{container} #{command.strip}
    DOCKER
    stdout, stderr, status = Open3.capture3(docker_command)
    if status.success?
      JSON.parse(stdout)
    else
      raise "Error extracting text: #{stderr}"
    end
  end

  # Extracts the text from the PDF file
  def extract
    doc_json = pdf2text(@file_path)
    @text_data = ""

    Parallel.each(doc_json["pages"], in_threads: THREADS) do |page|
      text = page["text"].gsub(/[^[:print:]]/, "")
      text = text.encode("UTF-8", invalid: :replace, undef: :replace, replace: "")
      @text_data += "#{text}\n"
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
