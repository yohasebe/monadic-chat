# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'fileutils'

require_relative '../../../apps/auto_forge/auto_forge_tools'
require_relative '../../../apps/auto_forge/agents/error_explainer'
require_relative '../../../apps/auto_forge/utils/codex_response_analyzer'

RSpec.describe AutoForgeTools do
  subject(:tool) do
    Class.new do
      include AutoForgeTools
    end.new
  end

  before do
    tool.instance_variable_set(:@context, {})
  end

  describe '#diagnose_and_suggest_fixes' do
    it 'returns an error message when project name is missing' do
      message = tool.diagnose_and_suggest_fixes({})

      expect(message).to include('❌ Diagnosis failed')
      expect(message).to include('Missing project name')
    end

    it 'stores diagnosis data when debug succeeds' do
      allow(tool).to receive(:debug_application_raw).and_return(
        success: true,
        project_name: 'TestApp',
        javascript_errors: [],
        warnings: [],
        summary: ['✅ Page loaded successfully'],
        performance: { loadTime: 120, renderTime: 80 },
        functionality_tests: []
      )

      tool.diagnose_and_suggest_fixes('spec' => { 'name' => 'TestApp' })

      diagnosis = tool.send(:current_diagnosis)
      expect(diagnosis).not_to be_nil
      expect(diagnosis[:project_name]).to eq('TestApp')
      expect(diagnosis[:explanations]).to be_empty
    end
  end

  describe '#apply_suggested_fixes' do
    it 'prompts to run diagnosis when no data is stored' do
      message = tool.apply_suggested_fixes('apply fixes')
      expect(message).to include('Please run diagnose_and_suggest_fixes')
    end

    it 'expires diagnosis after timeout and clears state' do
      diagnosis = {
        project_name: 'OldApp',
        debug_result: {},
        explanations: [],
        timestamp: Time.now - (AutoForgeTools::DIAGNOSIS_TIMEOUT + 60)
      }
      tool.instance_variable_set(:@last_diagnosis, diagnosis)
      tool.instance_variable_get(:@context)[:last_diagnosis] = diagnosis

      message = tool.apply_suggested_fixes('apply fixes')

      expect(message).to include('Diagnosis results have expired')
      expect(tool.send(:current_diagnosis)).to be_nil
    end

    it 'explains failure when GPT-5-Codex cannot generate fixes' do
      diagnosis = {
        project_name: 'TestApp',
        debug_result: { javascript_errors: [{ 'message' => 'Error' }] },
        explanations: [{ title: 'Issue', explanation: 'desc', impact: 'impact', severity: :high }],
        timestamp: Time.now
      }
      tool.instance_variable_set(:@last_diagnosis, diagnosis)
      tool.instance_variable_get(:@context)[:last_diagnosis] = diagnosis

      allow(tool).to receive(:call_gpt5_codex).and_return({ success: false, error: 'API timeout' })

      message = tool.apply_suggested_fixes('apply fixes')
      expect(message).to include('Failed to generate fixes')
      expect(message).to include('API timeout')
    end
  end

  describe '#apply_fix_with_backup' do
    let(:tmp_dir) { Dir.mktmpdir }
    let(:html_path) { File.join(tmp_dir, 'index.html') }

    before do
      File.write(html_path, '<!DOCTYPE html><html><body>original</body></html>')
    end

    after do
      FileUtils.remove_entry(tmp_dir)
    end

    it 'returns success message when Selenium is unavailable after applying fixes' do
      diagnosis = {
        project_name: 'TestApp',
        debug_result: { javascript_errors: [{ 'message' => 'error' }] },
        explanations: [],
        timestamp: Time.now
      }

      allow(tool).to receive(:write_full_file).and_return({ success: true })
      allow(tool).to receive(:debug_application_raw).and_return(
        success: false,
        error: 'Selenium container is not running'
      )

      result = tool.send(:apply_fix_with_backup, html_path, :full, '<!DOCTYPE html><html></html>', diagnosis)

      expect(result[:success]).to be(true)
      expect(result[:message]).to include('could not verify')
      expect(result[:message]).to include('Selenium is not available')
    end

    it 'restores backup when verification fails for other reasons' do
      diagnosis = {
        project_name: 'TestApp',
        debug_result: { javascript_errors: [{ 'message' => 'error' }] },
        explanations: [],
        timestamp: Time.now
      }

      allow(tool).to receive(:write_full_file).and_return({ success: true })
      allow(tool).to receive(:debug_application_raw).and_return(
        success: false,
        error: 'File not found'
      )
      allow(FileUtils).to receive(:mv).and_call_original

      result = tool.send(:apply_fix_with_backup, html_path, :full, '<!DOCTYPE html><html></html>', diagnosis)

      expect(result[:success]).to be(false)
      expect(result[:message]).to include('Original file restored')
      expect(FileUtils).to have_received(:mv).at_least(:once)
    end
  end
end
