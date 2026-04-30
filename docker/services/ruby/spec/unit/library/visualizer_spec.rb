# frozen_string_literal: true

require 'spec_helper'
require 'monadic/library'
require 'tmpdir'

RSpec.describe Monadic::Library::Visualizer do
  let(:store) { instance_double(Monadic::Library::Store) }

  before do
    allow(store).to receive(:visibility_filter) { |scope|
      case scope
      when :kb       then { must: [{ key: 'visibility', match: { any: %w[personal shareable] } }] }
      when :external then { must: [{ key: 'visibility', match: { value: 'shareable' } }] }
      end
    }
    allow(store).to receive(:conversation_filter) { |id|
      { must: [{ key: 'conversation_id', match: { value: id.to_s } }] }
    }
    allow(store).to receive(:combine_filters) { |*fs|
      m = fs.compact.flat_map { |f| Array(f[:must]) }
      m.empty? ? nil : { must: m }
    }
  end

  def trajectory_point(conv_id, turn_idx)
    {
      'id' => "pt-#{conv_id}-#{turn_idx}",
      'vector' => { 'content' => Array.new(768) { rand } },
      'payload' => { 'conversation_id' => conv_id, 'turn_idx' => turn_idx,
                     'visibility' => 'personal' }
    }
  end

  describe '.fetch_trajectory_points' do
    it 'paginates through scroll cursors and flattens vectors + turn_idx' do
      page1 = { points: [trajectory_point('c1', 0), trajectory_point('c1', 1)], next: 'cur' }
      page2 = { points: [trajectory_point('c1', 2)], next: nil }
      expect(store).to receive(:scroll).with(hash_including(offset: nil)).and_return(page1)
      expect(store).to receive(:scroll).with(hash_including(offset: 'cur')).and_return(page2)
      out = described_class.fetch_trajectory_points(store, 'c1')
      expect(out.map { |o| o['turn_idx'] }).to eq([0, 1, 2])
      expect(out.first['vector'].size).to eq(768)
    end
  end

  describe '.plot_trajectory' do
    let(:tmp_root) { Dir.mktmpdir('visualizer-test') }

    before do
      allow(Monadic::Utils::Environment).to receive(:shared_volume).and_return(tmp_root)
      allow(store).to receive(:scroll).and_return(
        { points: [trajectory_point('c1', 0), trajectory_point('c1', 1)], next: nil }
      )
    end

    after { FileUtils.remove_entry(tmp_root) }

    it 'stages an input JSON file under shared volume / library / inputs' do
      allow(described_class).to receive(:run_python_script).and_return(
        [JSON.dump(png_path: '/monadic/data/x.png', html_path: '/monadic/data/x.html',
                   conversations: [{ conversation_id: 'c1', label: 'c1', points: 2 }]) + "\n",
         instance_double(Process::Status, success?: true, exitstatus: 0)]
      )
      out = described_class.plot_trajectory(store: store, conversation_id: 'c1')

      expect(out[:points]).to eq(2)
      expect(out[:input_path]).to start_with(File.join(tmp_root, 'library', 'inputs'))
      expect(File.exist?(out[:input_path])).to be true

      written = JSON.parse(File.read(out[:input_path]))
      expect(written['conversations'].size).to eq(1)
      expect(written['conversations'].first['conversation_id']).to eq('c1')
      expect(written['conversations'].first['points'].size).to eq(2)
    end

    it 'translates container-side output paths back to host paths' do
      allow(described_class).to receive(:run_python_script).and_return(
        [JSON.dump(png_path: '/monadic/data/library/trajectories/x.png',
                   html_path: '/monadic/data/library/trajectories/x.html',
                   conversations: [{ conversation_id: 'c1', label: 'c1', points: 2 }]),
         instance_double(Process::Status, success?: true, exitstatus: 0)]
      )
      out = described_class.plot_trajectory(store: store, conversation_id: 'c1')
      expect(out[:png_path]).to start_with(tmp_root)
      expect(out[:html_path]).to start_with(tmp_root)
    end

    it 'raises ArgumentError when there is no trajectory data' do
      allow(store).to receive(:scroll).and_return(points: [], next: nil)
      expect { described_class.plot_trajectory(store: store, conversation_id: 'empty') }
        .to raise_error(ArgumentError, /No trajectory data/)
    end

    it 'surfaces python script errors' do
      allow(described_class).to receive(:run_python_script).and_return(
        ["traceback boom",
         instance_double(Process::Status, success?: false, exitstatus: 1)]
      )
      expect { described_class.plot_trajectory(store: store, conversation_id: 'c1') }
        .to raise_error(/exited with 1/)
    end

    it 'raises when the python script reports an error in its JSON payload' do
      allow(described_class).to receive(:run_python_script).and_return(
        [JSON.dump(error: 'no trajectory points'),
         instance_double(Process::Status, success?: true, exitstatus: 0)]
      )
      expect { described_class.plot_trajectory(store: store, conversation_id: 'c1') }
        .to raise_error(/Plot generation failed/)
    end
  end

  describe '.plot_cross_corpus' do
    let(:tmp_root) { Dir.mktmpdir('visualizer-cross') }

    before do
      allow(Monadic::Utils::Environment).to receive(:shared_volume).and_return(tmp_root)
      allow(store).to receive(:scroll) do |args|
        cid = args[:filter][:must].find { |f| f[:key] == 'conversation_id' }.dig(:match, :value)
        { points: [trajectory_point(cid, 0), trajectory_point(cid, 1)], next: nil }
      end
    end

    after { FileUtils.remove_entry(tmp_root) }

    it 'rejects an empty list' do
      expect { described_class.plot_cross_corpus(store: store, conversation_ids: []) }
        .to raise_error(ArgumentError, /non-empty array/)
    end

    it 'stages all conversations into a single input JSON' do
      allow(described_class).to receive(:run_python_script).and_return(
        [JSON.dump(png_path: '/monadic/data/x.png', html_path: '/monadic/data/x.html',
                   conversations: [{ conversation_id: 'a', label: 'a', points: 2 },
                                   { conversation_id: 'b', label: 'b', points: 2 }]),
         instance_double(Process::Status, success?: true, exitstatus: 0)]
      )
      out = described_class.plot_cross_corpus(
        store: store, conversation_ids: %w[a b],
        labels: { 'a' => 'Talk Alpha', 'b' => 'Talk Beta' }
      )

      written = JSON.parse(File.read(out[:input_path]))
      expect(written['conversations'].size).to eq(2)
      labels = written['conversations'].map { |c| c['label'] }
      expect(labels).to eq(['Talk Alpha', 'Talk Beta'])
    end
  end
end
