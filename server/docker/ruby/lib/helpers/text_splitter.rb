# frozen_string_literal: false

class TextSplitter
  THREADS = 4

  attr_reader :file_path, :text_data

  def initialize(text: nil, path: nil, max_tokens: 800, separator: "\n", overwrap_lines: 2)
    @file_path = path
    if text
      @text_data = text
    elsif @file_path && File.exist?(@file_path)
      @text_data = File.read(@file_path).gsub(/\R/, "\n")
    else
      raise "Either text or path must be provided"
    end
    @max_tokens = max_tokens
    @separator = separator
    @overwrap_lines = overwrap_lines
  end

  # Splits the text into chunks of `max_tokens` tokens
  # if overwrap_lines is set, it will add the specified number of lines
  # to the next chunk
  def split_text
    lines = @text_data.split(@separator)
    split_texts = []
    current_text = []
    current_tokens = 0

    last_n_lines = []

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

# If this file is run directly, it will split the text to files
# with less than half the maximum num of tokens
if $PROGRAM_NAME == __FILE__
  if ARGV.length != 1
    puts "Usage: ruby text_splitter.rb <file_path>"
    exit
  end

  file_path = ARGV[0]

  if File.exist?(file_path)
    doc = TextSplitter.new(path: file_path, max_tokens: 1000, separator: "\n\n", overwrap_lines: 2)
    split_texts = doc.split_text
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

