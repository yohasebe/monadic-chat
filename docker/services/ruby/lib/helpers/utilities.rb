# frozen_string_literal: true

module UtilitiesHelper
  module_function

  # language detection using CLD gem
  def detect_language(text)
    CLD.detect_language(text)[:code]
  end

  # Convert markdown to HTML
  def markdown_to_html(text, mathjax: false)
    text = text.gsub(/\[^([0-9])^\]/) { "[^#{Regexp.last_match(1)}]" }
    text = text.gsub(/(!\[[^\]]*\]\()(['"])([^\s)]+)(['"])(\))/, '\1\3\5')

    if mathjax
      Kramdown::Document.new(text, syntax_highlighter: :rouge, input: "GFM", syntax_highlighter_ops: { guess_lang: true, math_engine: "mathjax" }).to_html
    else
      Kramdown::Document.new(text, syntax_highlighter: :rouge, input: "GFM", syntax_highlighter_ops: { guess_lang: true }).to_html
    end
  end
end
