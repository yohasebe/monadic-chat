require 'spec_helper'
require_relative '../lib/monadic/utils/error_pattern_detector'

RSpec.describe ErrorPatternDetector do
  let(:session) { {} }

  describe '.initialize_session' do
    it 'initializes error tracking in session' do
      described_class.initialize_session(session)
      expect(session[:error_patterns]).to include(
        history: [],
        similar_count: 0,
        last_pattern: nil
      )
    end
  end

  describe '.add_error' do
    before { described_class.initialize_session(session) }

    it 'adds error to history' do
      described_class.add_error(session, 'Font family not found', 'run_code')
      expect(session[:error_patterns][:history].size).to eq(1)
      expect(session[:error_patterns][:history].first[:error]).to eq('Font family not found')
    end

    it 'detects font error pattern' do
      described_class.add_error(session, 'findfont: Font family "Arial" not found', 'run_code')
      expect(session[:error_patterns][:last_pattern]).to eq(:font_error)
    end

    it 'increments similar_count for repeated patterns' do
      described_class.add_error(session, 'findfont: Font family "Arial" not found', 'run_code')
      described_class.add_error(session, 'findfont: Font family "Helvetica" not found', 'run_code')
      described_class.add_error(session, 'Cannot find font Times', 'run_code')
      
      expect(session[:error_patterns][:similar_count]).to eq(2)
    end

    it 'resets similar_count for different patterns' do
      described_class.add_error(session, 'findfont: Font family not found', 'run_code')
      described_class.add_error(session, 'No module named numpy', 'run_code')
      
      expect(session[:error_patterns][:similar_count]).to eq(0)
    end

    it 'keeps only last 10 errors' do
      15.times do |i|
        described_class.add_error(session, "Error #{i}", 'run_code')
      end
      
      expect(session[:error_patterns][:history].size).to eq(10)
    end
  end

  describe '.should_stop_retrying?' do
    before { described_class.initialize_session(session) }

    it 'returns false when similar_count < 3' do
      2.times do
        described_class.add_error(session, 'Font not found', 'run_code')
      end
      
      expect(described_class.should_stop_retrying?(session)).to be false
    end

    it 'returns true when similar_count >= 3' do
      3.times do
        described_class.add_error(session, 'Font not found', 'run_code')
      end
      
      expect(described_class.should_stop_retrying?(session)).to be true
    end
  end

  describe '.get_error_suggestion' do
    before { described_class.initialize_session(session) }

    it 'returns font-specific suggestion for font errors' do
      3.times do
        described_class.add_error(session, 'findfont: Font family not found', 'run_code')
      end
      
      suggestion = described_class.get_error_suggestion(session)
      expect(suggestion).to include('font-related errors')
      expect(suggestion).to include('DejaVu Sans')
    end

    it 'returns module-specific suggestion for import errors' do
      3.times do
        described_class.add_error(session, 'No module named pandas', 'run_code')
      end
      
      suggestion = described_class.get_error_suggestion(session)
      expect(suggestion).to include('module import errors')
      expect(suggestion).to include('pip install')
    end

    it 'returns general suggestion for unrecognized patterns' do
      session[:error_patterns][:history] = [
        { error: 'Unknown error 1', timestamp: Time.now, function: 'test' },
        { error: 'Unknown error 2', timestamp: Time.now, function: 'test' }
      ]
      session[:error_patterns][:last_pattern] = :unknown
      
      suggestion = described_class.get_error_suggestion(session)
      expect(suggestion).to include('repeated errors')
      expect(suggestion).to include('different approach')
    end
  end
end