# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../../lib/monadic/adapters/vendors/gemini_helper'

# format_lyria_lyrics renders Lyria 3's raw timed-lyrics format (section markers
# "[[A0]]", per-line timestamps "[0.0:]", continuation markers "[:]") as a
# readable timed lyric sheet: section starts keep a "[m:ss]" prefix, continuation
# lines are indented to align, and section markers become blank-line breaks.
RSpec.describe 'GeminiHelper#format_lyria_lyrics' do
  subject(:helper) do
    Class.new do
      include GeminiHelper
    end.new
  end

  def fmt(raw)
    helper.format_lyria_lyrics(raw)
  end

  it 'returns empty string for instrumental tracks' do
    expect(fmt('<instrumental>')).to eq('')
    expect(fmt(' <instrumental> ')).to eq('')
  end

  it 'returns empty string for nil/blank input' do
    expect(fmt(nil)).to eq('')
    expect(fmt('   ')).to eq('')
  end

  it 'converts seconds timestamps to [m:ss] and aligns continuation lines' do
    raw = "[0.0:] First line\n[:] Second line"
    expect(fmt(raw)).to eq("[0:00] First line\n       Second line")
  end

  it 'formats minutes correctly for later timestamps' do
    raw = "[96.0:] Late line"
    expect(fmt(raw)).to eq("[1:36] Late line")
  end

  it 'turns section markers into blank-line breaks while keeping timestamps' do
    raw = <<~RAW
      [[A0]]
      [0.0:] Line one
      [:] Line two
      [[B1]]
      [24.0:] Chorus line
    RAW
    expect(fmt(raw)).to eq("[0:00] Line one\n       Line two\n\n[0:24] Chorus line")
  end

  it 'renders the real dogfood example: timestamps kept, raw codes gone' do
    raw = "[[A0]]\n[0.0:] 朝の光を浴びて 走り出すハイウェイ\n[:] お気に入りのプレイリスト 窓を開けてさ\n[[B1]]\n[24.0:] ロードトリップ 終わらない夢を乗せて\n[:] (どこまでも行ける 二人なら)"
    result = fmt(raw)
    expect(result).not_to match(/\[\[|\[:\]|\[\d+\.\d/)   # no raw section/continuation/seconds codes
    expect(result).to include('[0:00] 朝の光を浴びて 走り出すハイウェイ')
    expect(result).to include('[0:24] ロードトリップ 終わらない夢を乗せて')
    expect(result).to include("\n\n")                      # section break preserved
  end
end
