# frozen_string_literal: true

require 'tempfile'

# Load the lint script as a library (skip the main execution at the bottom)
require_relative '../../../../../../scripts/lint/check_model_consistency'

RSpec.describe ModelConsistency do
  let(:spec) { ModelConsistency::SpecLoader.load }

  describe ModelConsistency::SpecLoader do
    describe '.load' do
      it 'parses model_spec.js and returns a non-empty hash' do
        expect(spec).to be_a(Hash)
        expect(spec.size).to be > 0
      end

      it 'includes known models' do
        expect(spec).to have_key('gpt-4o')
        expect(spec).to have_key('gpt-4o-mini')
        expect(spec).to have_key('claude-sonnet-4-6')
      end
    end

    describe '.deprecated_models' do
      it 'returns only deprecated models' do
        deprecated = ModelConsistency::SpecLoader.deprecated_models(spec)
        expect(deprecated).to be_a(Hash)
        deprecated.each do |_, props|
          expect(props['deprecated']).to eq(true)
        end
      end

      it 'includes known deprecated models' do
        deprecated = ModelConsistency::SpecLoader.deprecated_models(spec)
        expect(deprecated).to have_key('gpt-4o')
        expect(deprecated).to have_key('grok-3')
      end
    end

    describe '.sunset_info' do
      it 'returns sunset_date and successor for deprecated models' do
        info = ModelConsistency::SpecLoader.sunset_info(spec, 'gpt-4o')
        expect(info[:sunset_date]).to eq('2026-06-30')
        expect(info[:successor]).to eq('gpt-4.1')
      end

      it 'returns nils for models without lifecycle data' do
        info = ModelConsistency::SpecLoader.sunset_info(spec, 'claude-sonnet-4-6')
        expect(info[:sunset_date]).to be_nil
        expect(info[:successor]).to be_nil
      end
    end
  end

  describe ModelConsistency::MdslChecker do
    describe '.extract_models_from_mdsl' do
      it 'extracts single model declarations' do
        tmpfile = Tempfile.new(['test', '.mdsl'])
        tmpfile.write(%(    model "gpt-5.4"\n))
        tmpfile.close

        results = ModelConsistency::MdslChecker.extract_models_from_mdsl(Pathname.new(tmpfile.path))
        expect(results.size).to eq(1)
        expect(results[0][:model]).to eq('gpt-5.4')
        expect(results[0][:line]).to eq(1)
      ensure
        tmpfile&.unlink
      end

      it 'extracts array model declarations' do
        tmpfile = Tempfile.new(['test', '.mdsl'])
        tmpfile.write(%(    model ["gpt-5.4", "gpt-5.2", "gpt-4.1"]\n))
        tmpfile.close

        results = ModelConsistency::MdslChecker.extract_models_from_mdsl(Pathname.new(tmpfile.path))
        expect(results.size).to eq(3)
        expect(results.map { |r| r[:model] }).to eq(%w[gpt-5.4 gpt-5.2 gpt-4.1])
      ensure
        tmpfile&.unlink
      end
    end

    describe '.check' do
      it 'returns an array of issues' do
        issues = ModelConsistency::MdslChecker.check(spec)
        expect(issues).to be_an(Array)
        issues.each do |issue|
          expect(issue).to be_a(ModelConsistency::Issue)
          expect([:mdsl_deprecated, :mdsl_unknown]).to include(issue.category)
        end
      end
    end

    describe '.model_exists_in_spec?' do
      it 'finds direct model names' do
        expect(ModelConsistency::MdslChecker.model_exists_in_spec?(spec, 'gpt-4o')).to be true
      end

      it 'finds models via normalization' do
        # Dated variants should resolve to base model
        expect(ModelConsistency::MdslChecker.model_exists_in_spec?(spec, 'claude-sonnet-4-6')).to be true
      end

      it 'returns false for unknown models' do
        expect(ModelConsistency::MdslChecker.model_exists_in_spec?(spec, 'totally-fake-model')).to be false
      end
    end
  end

  describe ModelConsistency::DefaultsChecker do
    describe '.check' do
      it 'returns an array of issues' do
        issues = ModelConsistency::DefaultsChecker.check(spec)
        expect(issues).to be_an(Array)
        issues.each do |issue|
          expect(issue).to be_a(ModelConsistency::Issue)
          expect([:defaults_deprecated, :defaults_unknown]).to include(issue.category)
        end
      end
    end
  end

  describe ModelConsistency::SunsetChecker do
    describe '.check' do
      it 'returns sunset-related issues' do
        issues = ModelConsistency::SunsetChecker.check(spec)
        expect(issues).to be_an(Array)
        issues.each do |issue|
          expect([:sunset_passed, :sunset_passed_deprecated, :sunset_approaching, :sunset_invalid]).to include(issue.category)
        end
      end

      it 'detects past sunset dates (deprecated model → warning category)' do
        test_spec = {
          'old-model' => {
            'deprecated' => true,
            'sunset_date' => '2020-01-01',
            'successor' => 'new-model'
          }
        }
        issues = ModelConsistency::SunsetChecker.check(test_spec)
        passed = issues.select { |i| i.category == :sunset_passed_deprecated }
        expect(passed.size).to eq(1)
        expect(passed[0].model).to eq('old-model')
      end

      it 'detects past sunset dates (not deprecated → error category)' do
        test_spec = {
          'forgotten-model' => {
            'sunset_date' => '2020-01-01'
          }
        }
        issues = ModelConsistency::SunsetChecker.check(test_spec)
        passed = issues.select { |i| i.category == :sunset_passed }
        expect(passed.size).to eq(1)
        expect(passed[0].model).to eq('forgotten-model')
        expect(passed[0].message).to include('not marked as deprecated')
      end

      it 'detects approaching sunset dates' do
        near_date = (Date.today + 15).to_s
        test_spec = {
          'soon-model' => {
            'deprecated' => true,
            'sunset_date' => near_date,
            'successor' => 'next-model'
          }
        }
        issues = ModelConsistency::SunsetChecker.check(test_spec)
        approaching = issues.select { |i| i.category == :sunset_approaching }
        expect(approaching.size).to eq(1)
        expect(approaching[0].model).to eq('soon-model')
      end

      it 'detects invalid sunset date format' do
        test_spec = {
          'bad-model' => { 'sunset_date' => 'not-a-date' }
        }
        issues = ModelConsistency::SunsetChecker.check(test_spec)
        invalid = issues.select { |i| i.category == :sunset_invalid }
        expect(invalid.size).to eq(1)
      end
    end
  end

  describe ModelConsistency::AgentChecker do
    describe '.check' do
      it 'returns agent-related issues' do
        issues = ModelConsistency::AgentChecker.check(spec)
        expect(issues).to be_an(Array)
        issues.each do |issue|
          expect(issue.category).to eq(:agent_deprecated)
        end
      end
    end

    describe '.collect_files' do
      it 'returns an array of Pathname objects' do
        files = ModelConsistency::AgentChecker.collect_files
        expect(files).to be_an(Array)
        files.each do |f|
          expect(f).to be_a(Pathname)
          expect(f.extname).to eq('.rb')
        end
      end
    end
  end
end
