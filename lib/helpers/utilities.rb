# frozen_string_literal: true

module UtilitiesHelper
  # language detection using CLD gem
  def detect_language(text)
    CLD.detect_language(text)[:code]
  end

  # Convert markdown to HTML
  def markdown_to_html(text)
    text = text.gsub(/\[^([0-9])^\]/) { "[^#{Regexp.last_match(1)}]" }
    Kramdown::Document.new(text, syntax_highlighter: :rouge, input: "GFM", syntax_highlighter_ops: {}).to_html
  end
end
