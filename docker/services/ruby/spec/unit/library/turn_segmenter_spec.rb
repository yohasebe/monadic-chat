# frozen_string_literal: true

require 'spec_helper'
require 'monadic/library'

RSpec.describe Monadic::Library::TurnSegmenter do
  def conv(messages, participants = nil)
    {
      'messages' => messages,
      'participants' => participants || infer_participants(messages)
    }
  end

  def infer_participants(messages)
    messages.map { |m| m.dig('speaker', 'id') }.uniq.compact.map { |id| { 'id' => id, 'role' => 'human' } }
  end

  def msg(id, speaker, text, timing = nil)
    h = { 'id' => id, 'speaker' => { 'id' => speaker }, 'text' => text }
    h['timing'] = timing if timing
    h
  end

  describe '.segment (multi-speaker)' do
    it 'returns one turn per consecutive speaker block' do
      input = conv([
        msg('m1', 'alice', 'hi'),
        msg('m2', 'alice', 'how are you?'),
        msg('m3', 'bob', 'good'),
        msg('m4', 'alice', 'great')
      ])
      turns = described_class.segment(input)
      expect(turns.size).to eq(3)
      expect(turns.map { |t| t[:speaker_id] }).to eq(%w[alice bob alice])
      expect(turns.first[:text]).to eq("hi\nhow are you?")
      expect(turns.first[:message_count]).to eq(2)
    end

    it 'records start/end message ids on each turn' do
      input = conv([
        msg('m1', 'alice', 'a'),
        msg('m2', 'alice', 'b'),
        msg('m3', 'bob', 'c')
      ])
      turns = described_class.segment(input)
      expect(turns[0][:start_message_id]).to eq('m1')
      expect(turns[0][:end_message_id]).to eq('m2')
      expect(turns[1][:start_message_id]).to eq('m3')
      expect(turns[1][:end_message_id]).to eq('m3')
    end

    it 'looks up speaker_role from the participants array' do
      participants = [
        { 'id' => 'alice', 'role' => 'human' },
        { 'id' => 'bot',   'role' => 'assistant' }
      ]
      input = conv([msg('m1', 'alice', 'hi'), msg('m2', 'bot', 'hello')], participants)
      roles = described_class.segment(input).map { |t| t[:speaker_role] }
      expect(roles).to eq(%w[human assistant])
    end
  end

  describe '.segment (monologue)' do
    it 'returns one turn per message when only one speaker is present' do
      input = conv([
        msg('m1', 'speaker-1', 'opening'),
        msg('m2', 'speaker-1', 'middle'),
        msg('m3', 'speaker-1', 'closing')
      ])
      turns = described_class.segment(input)
      expect(turns.size).to eq(3)
      expect(turns.map { |t| t[:text] }).to eq(%w[opening middle closing])
    end

    it 'preserves timing for talk-style monologues' do
      input = conv([
        msg('m1', 'speaker-1', 'a', { 'offset_seconds' => 0.0, 'duration_seconds' => 2.0 }),
        msg('m2', 'speaker-1', 'b', { 'offset_seconds' => 2.0, 'duration_seconds' => 3.0 })
      ])
      turns = described_class.segment(input)
      expect(turns.first[:start_offset_seconds]).to eq(0.0)
      expect(turns.first[:end_offset_seconds]).to eq(2.0) # offset + duration
      expect(turns.last[:start_offset_seconds]).to eq(2.0)
      expect(turns.last[:end_offset_seconds]).to eq(5.0)
    end
  end

  describe 'edge cases' do
    it 'returns [] for an empty messages array' do
      expect(described_class.segment(conv([]))).to eq([])
    end

    it 'falls back to "other" when speaker is not in participants' do
      input = { 'messages' => [msg('m1', 'unknown', 'hi')], 'participants' => [] }
      turns = described_class.segment(input)
      expect(turns.first[:speaker_role]).to eq('other')
    end
  end
end
