# frozen_string_literal: true

require "spec_helper"
require_relative "../../../apps/mermaid_grapher/mermaid_grapher_tools"

# CJK-safety invariant for Mermaid source sanitization.
#
# Background (2026-06-02): the "smart punctuation → ASCII" folding in both the
# server-side `sanitize_mermaid_code` (this module) and the frontend
# `sanitizeMermaidSource` (ws-content-renderer.js) wrongly included CJK
# characters that merely *look like* Western punctuation:
#   - U+30FC ー  (Japanese long-vowel mark, e.g. クロマトグラフィー)
#   - U+300C 「 / U+300D 」 (corner brackets)
# Folding them to '-' / '"' corrupted Japanese node labels (クロマトグラフィー →
# クロマトグラフィ-) and made Mermaid 11.x throw "Syntax error in text" — even
# though server validation had passed, because validation and rendering used
# different text. These specs pin the corrected behavior so the regression
# cannot silently return. The frontend half is pinned by the matching Jest
# spec in test/frontend/websocket-utilities.test.js.
RSpec.describe "MermaidGrapherTools#sanitize_mermaid_code CJK safety" do
  let(:test_class) { Class.new { include MermaidGrapherTools } }
  let(:tools) { test_class.new }

  def sanitize(code)
    tools.send(:sanitize_mermaid_code, code)
  end

  describe "preserves CJK characters that resemble Western punctuation" do
    it "keeps the long-vowel mark ー (U+30FC) intact" do
      expect(sanitize("ー")).to eq("ー")
      expect(sanitize("クロマトグラフィー")).to eq("クロマトグラフィー")
    end

    it "keeps corner brackets 「」 (U+300C/U+300D) intact" do
      expect(sanitize("「重要」")).to eq("「重要」")
    end

    it "renders a Japanese mindmap node line without corruption" do
      code = "mindmap\n  root((化学))\n    分析化学\n      クロマトグラフィー\n"
      expect(sanitize(code)).to include("クロマトグラフィー")
      expect(sanitize(code)).not_to include("クロマトグラフィ-")
    end
  end

  describe "still folds genuine Western smart punctuation to ASCII" do
    it "normalizes typographic dashes (en/em/minus/fullwidth) to '-'" do
      expect(sanitize("A–B—C−D－E")).to eq("A-B-C-D-E")
    end

    it "normalizes curly single quotes to ASCII apostrophe" do
      expect(sanitize("‘x’")).to eq("'x'")
    end

    it "normalizes curly double quotes to ASCII quote" do
      expect(sanitize("“x”")).to eq('"x"')
    end
  end

  # Source-level guard: even if someone "helpfully" re-adds the CJK code points
  # to a future fold rule, this catches it without needing a runtime example for
  # every label shape. Mirrors the grep-walk invariant pattern used elsewhere.
  describe "source does not fold CJK code points" do
    source = File.read(
      File.expand_path("../../../apps/mermaid_grapher/mermaid_grapher_tools.rb", __dir__)
    )
    # Inspect the punctuation-folding gsub rules (lines that map a character
    # class onto an ASCII dash/quote). In this file they use literal dash/quote
    # variants inside the class, e.g. gsub(/[‐-―−－]/, '-').
    fold_lines = source.lines.select do |l|
      l.include?("gsub(") && l =~ /,\s*(['"]).\1\)/
    end

    it "has fold rules to check" do
      expect(fold_lines).not_to be_empty
    end

    it "no fold rule contains U+30FC (ー) or U+300C/U+300D (「」)" do
      offenders = fold_lines.select do |l|
        l.include?("ー") || l.include?("「") || l.include?("」") ||
          l =~ /\\u30FC|\\u300C|\\u300D/i
      end
      expect(offenders).to be_empty,
        "CJK code points must not appear in Mermaid fold rules:\n#{offenders.join}"
    end
  end
end
