# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../../lib/monadic/adapters/vendors/gemini_helper'

# Gemini generation APIs return HTTP 200 with no usable media when a prompt is
# blocked (e.g. it names a specific artist/work). The reason lives in the
# response body (promptFeedback.blockReason / candidates[].finishReason for
# generateContent; raiFilteredReason for Imagen's predict API). These helpers
# turn that into an actionable message so the failure card explains *why*,
# instead of a generic "no X returned".
RSpec.describe 'GeminiHelper block-reason helpers' do
  subject(:helper) { Class.new { include GeminiHelper }.new }

  describe '#gemini_block_reason' do
    it 'reports PROHIBITED_CONTENT with image-specific guidance for kind: :image' do
      msg = helper.gemini_block_reason(
        { 'promptFeedback' => { 'blockReason' => 'PROHIBITED_CONTENT' } }, kind: :image
      )
      expect(msg).to include('PROHIBITED_CONTENT')
      expect(msg).to match(/artist|artwork|identifiable person|copyrighted/i)
    end

    it 'reports PROHIBITED_CONTENT with audio-specific guidance for kind: :audio' do
      msg = helper.gemini_block_reason(
        { 'promptFeedback' => { 'blockReason' => 'PROHIBITED_CONTENT' } }, kind: :audio
      )
      expect(msg).to include('PROHIBITED_CONTENT')
      expect(msg).to match(/genre|instruments|artist/i)
    end

    it 'handles the image-only IMAGE_SAFETY finishReason' do
      msg = helper.gemini_block_reason(
        { 'candidates' => [{ 'finishReason' => 'IMAGE_SAFETY' }] }, kind: :image
      )
      expect(msg).to include('IMAGE_SAFETY')
    end

    it 'falls back with the noun for the kind when no reason is present' do
      expect(helper.gemini_block_reason({}, kind: :image)).to match(/No image was returned/i)
      expect(helper.gemini_block_reason({}, kind: :audio)).to match(/No audio was returned/i)
    end

    it 'appends a server-provided blockReasonMessage' do
      msg = helper.gemini_block_reason(
        { 'promptFeedback' => { 'blockReason' => 'PROHIBITED_CONTENT',
                                'blockReasonMessage' => 'Server detail here.' } }, kind: :image
      )
      expect(msg).to include('Server detail here.')
    end
  end

  describe '#imagen_block_reason' do
    it 'surfaces raiFilteredReason from predictions' do
      msg = helper.imagen_block_reason(
        { 'predictions' => [{ 'raiFilteredReason' => 'Filtered: celebrity likeness.' }] }
      )
      expect(msg).to include('Filtered: celebrity likeness.')
    end

    it 'surfaces a top-level raiFilteredReason' do
      msg = helper.imagen_block_reason({ 'raiFilteredReason' => 'Top-level filter note.' })
      expect(msg).to include('Top-level filter note.')
    end

    it 'gives actionable guidance when no filter reason is reported' do
      msg = helper.imagen_block_reason({ 'predictions' => [] })
      expect(msg).to match(/filtered|restricted content|describe/i)
    end
  end
end
