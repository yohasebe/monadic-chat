# frozen_string_literal: true

require 'spec_helper'
require 'monadic/library'

RSpec.describe Monadic::Library::Trajectory do
  def turn(idx, text)
    { turn_idx: idx, text: text, speaker_id: 'x', speaker_role: 'human',
      start_message_id: "m#{idx}", end_message_id: "m#{idx}", message_count: 1 }
  end

  describe '.build_windows' do
    let(:turns) { (0..4).map { |i| turn(i, "T#{i}") } }

    it 'produces one window per turn' do
      windows = described_class.build_windows(turns, window_size: 3)
      expect(windows.size).to eq(turns.size)
      expect(windows.map { |w| w[:turn_idx] }).to eq([0, 1, 2, 3, 4])
    end

    it 'uses the full window once enough history is available' do
      windows = described_class.build_windows(turns, window_size: 3)
      w3 = windows[3]
      expect(w3[:start_turn_idx]).to eq(1)
      expect(w3[:end_turn_idx]).to eq(3)
      expect(w3[:window_size]).to eq(3)
      expect(w3[:text]).to eq("T1\n\nT2\n\nT3")
    end

    it 'clips the window at the start of the conversation' do
      windows = described_class.build_windows(turns, window_size: 3)
      w0 = windows[0]
      expect(w0[:start_turn_idx]).to eq(0)
      expect(w0[:window_size]).to eq(1)
      expect(w0[:text]).to eq('T0')

      w1 = windows[1]
      expect(w1[:start_turn_idx]).to eq(0)
      expect(w1[:window_size]).to eq(2)
      expect(w1[:text]).to eq("T0\n\nT1")
    end

    it 'supports window_size = 1 (each turn gets just itself)' do
      windows = described_class.build_windows(turns, window_size: 1)
      expect(windows.map { |w| w[:text] }).to eq(%w[T0 T1 T2 T3 T4])
    end

    it 'returns [] for empty turns' do
      expect(described_class.build_windows([], window_size: 3)).to eq([])
    end

    it 'rejects window_size < 1' do
      expect { described_class.build_windows(turns, window_size: 0) }
        .to raise_error(ArgumentError, /window_size/)
    end
  end
end
