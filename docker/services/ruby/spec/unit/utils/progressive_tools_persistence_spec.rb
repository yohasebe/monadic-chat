# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../lib/monadic/utils/progressive_tool_manager'

# Dynamic-skill unlock state is volatile (in-memory, per Rack session). For
# reproducibility, an exported session round-trips the unlocked tool lists so
# reopening it restores the skills the model had acquired.
RSpec.describe 'ProgressiveToolManager unlock persistence' do
  let(:mgr) { Monadic::Utils::ProgressiveToolManager }

  describe '.export_unlocked' do
    it 'returns nil when nothing has been unlocked' do
      expect(mgr.export_unlocked({})).to be_nil
      expect(mgr.export_unlocked({ progressive_tools: {} })).to be_nil
      expect(mgr.export_unlocked({ progressive_tools: { "App" => { unlocked: [] } } })).to be_nil
    end

    it 'serializes only the unlocked lists, dropping transient bookkeeping' do
      session = {
        progressive_tools: {
          "SkillLoaderTest" => {
            unlocked: %w[search_web tavily_search],
            triggered_events: [:some_event],
            scanned_count: 3
          }
        }
      }
      expect(mgr.export_unlocked(session)).to eq("SkillLoaderTest" => %w[search_web tavily_search])
    end
  end

  describe '.import_unlocked' do
    it 'restores unlock state into a fresh session' do
      session = {}
      mgr.import_unlocked(session, "SkillLoaderTest" => %w[search_web tavily_search])
      state = session[:progressive_tools]["SkillLoaderTest"]
      expect(state[:unlocked]).to include("search_web", "tavily_search")
      # Standard shape is rebuilt so visible_tools works immediately.
      expect(state[:triggered_events]).to eq([])
      expect(state[:scanned_count]).to eq(0)
    end

    it 'is idempotent and does not duplicate already-unlocked tools' do
      session = {}
      mgr.import_unlocked(session, "App" => %w[a b])
      mgr.import_unlocked(session, "App" => %w[b c])
      expect(session[:progressive_tools]["App"][:unlocked]).to eq(%w[a b c])
    end

    it 'is a no-op for blank or malformed data' do
      session = {}
      expect { mgr.import_unlocked(session, nil) }.not_to raise_error
      expect { mgr.import_unlocked(session, "App" => []) }.not_to raise_error
      expect(session[:progressive_tools]).to be_nil
    end
  end

  it 'round-trips export -> import losslessly for the unlocked lists' do
    original = {
      progressive_tools: {
        "AppA" => { unlocked: %w[search_web], triggered_events: [], scanned_count: 1 },
        "AppB" => { unlocked: %w[fetch_web_content library_search], triggered_events: [], scanned_count: 5 }
      }
    }
    exported = mgr.export_unlocked(original)

    restored = {}
    mgr.import_unlocked(restored, exported)

    expect(restored[:progressive_tools]["AppA"][:unlocked]).to eq(%w[search_web])
    expect(restored[:progressive_tools]["AppB"][:unlocked]).to eq(%w[fetch_web_content library_search])
  end
end
