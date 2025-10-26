# frozen_string_literal: true

require_relative '../../../lib/monadic/utils/system_prompt_injector'
require_relative '../../../lib/monadic/utils/language_config'

RSpec.describe Monadic::Utils::SystemPromptInjector do
  describe '.build_injections' do
    context 'with system context' do
      context 'with no conditions met' do
        it 'returns empty array' do
          session = {}
          options = {}

          result = described_class.build_injections(session: session, options: options, context: :system)

          expect(result).to eq([])
        end
      end
    end

    context 'with user context' do
      context 'with no prompt_suffix' do
        it 'returns empty array' do
          session = {}
          options = {}

          result = described_class.build_injections(session: session, options: options, context: :user)

          expect(result).to eq([])
        end
      end

      context 'with prompt_suffix' do
        it 'includes prompt_suffix injection' do
          session = {}
          options = { prompt_suffix: 'Please be concise.' }

          result = described_class.build_injections(session: session, options: options, context: :user)

          expect(result.length).to eq(1)
          expect(result[0][:name]).to eq(:prompt_suffix)
          expect(result[0][:content]).to eq('Please be concise.')
        end
      end

      context 'with empty prompt_suffix' do
        it 'excludes prompt_suffix injection' do
          session = {}
          options = { prompt_suffix: '' }

          result = described_class.build_injections(session: session, options: options, context: :user)

          expect(result).to be_empty
        end
      end
    end

    context 'with language preference set' do
      it 'includes language injection' do
        session = {
          runtime_settings: { language: 'ja' }
        }
        options = {}

        result = described_class.build_injections(session: session, options: options)

        expect(result.length).to eq(1)
        expect(result[0][:name]).to eq(:language_preference)
        expect(result[0][:content]).to include('Japanese')
      end

      it 'excludes language injection when set to auto' do
        session = {
          runtime_settings: { language: 'auto' }
        }
        options = {}

        result = described_class.build_injections(session: session, options: options)

        expect(result).to be_empty
      end
    end

    context 'with websearch enabled' do
      it 'includes websearch injection for non-reasoning models' do
        session = {}
        options = {
          websearch_enabled: true,
          reasoning_model: false,
          websearch_prompt: 'Use web search effectively.'
        }

        result = described_class.build_injections(session: session, options: options)

        expect(result.length).to eq(1)
        expect(result[0][:name]).to eq(:websearch)
        expect(result[0][:content]).to eq('Use web search effectively.')
      end

      it 'excludes websearch injection for reasoning models' do
        session = {}
        options = {
          websearch_enabled: true,
          reasoning_model: true,
          websearch_prompt: 'Use web search effectively.'
        }

        result = described_class.build_injections(session: session, options: options)

        expect(result).to be_empty
      end
    end

    context 'with STT diarization model' do
      it 'includes diarization warning when stt_model contains "diarize"' do
        session = {
          parameters: { "stt_model" => "gpt-4o-transcribe-diarize" }
        }
        options = {}

        result = described_class.build_injections(session: session, options: options)

        expect(result.length).to eq(1)
        expect(result[0][:name]).to eq(:stt_diarization_warning)
        expect(result[0][:content]).to include('Speaker Diarization Context')
        expect(result[0][:content]).to include('Do NOT adopt the role of any labeled speaker')
      end

      it 'excludes diarization warning for non-diarize models' do
        session = {
          parameters: { "stt_model" => "gpt-4o-mini-transcribe" }
        }
        options = {}

        result = described_class.build_injections(session: session, options: options)

        expect(result).to be_empty
      end
    end

    context 'with MathJax enabled' do
      it 'includes MathJax prompt with regular escaping for standard mode' do
        session = {
          parameters: { "mathjax" => true }
        }
        options = {}

        result = described_class.build_injections(session: session, options: options)

        expect(result.length).to eq(1)
        expect(result[0][:name]).to eq(:mathjax)
        expect(result[0][:content]).to include('MathJax notation')
        expect(result[0][:content]).to include('\\frac{k(k + 1)}{2}')  # Single backslash (literal)
        expect(result[0][:content]).not_to include('\\\\frac')  # Not double-escaped
        expect(result[0][:content]).to include('\\begin{itemize}')  # Includes limitations
      end

      it 'includes MathJax prompt with extra escaping for monadic mode' do
        session = {
          parameters: { "mathjax" => true, "monadic" => true }
        }
        options = {}

        result = described_class.build_injections(session: session, options: options)

        expect(result.length).to eq(1)
        expect(result[0][:name]).to eq(:mathjax)
        expect(result[0][:content]).to include('MathJax notation')
        expect(result[0][:content]).to include('\\\\frac')  # Double backslash (literal) for JSON escaping
        expect(result[0][:content]).to include('Make sure to escape properly')
        expect(result[0][:content]).not_to include('\\begin{itemize}')  # No limitations section
      end

      it 'includes MathJax prompt with extra escaping for jupyter mode' do
        session = {
          parameters: { "mathjax" => true, "jupyter" => true }
        }
        options = {}

        result = described_class.build_injections(session: session, options: options)

        expect(result.length).to eq(1)
        expect(result[0][:name]).to eq(:mathjax)
        expect(result[0][:content]).to include('MathJax notation')
        expect(result[0][:content]).to include('\\\\frac')  # Double backslash (literal) for JSON escaping
        expect(result[0][:content]).to include('Make sure to escape properly')
      end

      it 'excludes MathJax prompt when mathjax is false' do
        session = {
          parameters: { "mathjax" => false }
        }
        options = {}

        result = described_class.build_injections(session: session, options: options)

        expect(result).to be_empty
      end
    end

    context 'with system_prompt_suffix' do
      it 'includes system_prompt_suffix when provided' do
        session = {}
        options = {
          system_prompt_suffix: 'Always be concise.'
        }

        result = described_class.build_injections(session: session, options: options)

        expect(result.length).to eq(1)
        expect(result[0][:name]).to eq(:system_prompt_suffix)
        expect(result[0][:content]).to eq('Always be concise.')
      end

      it 'excludes system_prompt_suffix when empty' do
        session = {}
        options = {
          system_prompt_suffix: ''
        }

        result = described_class.build_injections(session: session, options: options)

        expect(result).to be_empty
      end
    end

    context 'with multiple conditions met' do
      it 'returns injections in priority order' do
        session = {
          runtime_settings: { language: 'en' },
          parameters: {
            "stt_model" => "gpt-4o-transcribe-diarize",
            "mathjax" => true
          }
        }
        options = {
          websearch_enabled: true,
          reasoning_model: false,
          websearch_prompt: 'Web search prompt',
          system_prompt_suffix: 'Custom suffix'
        }

        result = described_class.build_injections(session: session, options: options)

        expect(result.length).to eq(5)
        # Check priority order: language(100) > websearch(80) > diarization(60) > mathjax(50) > suffix(40)
        expect(result[0][:name]).to eq(:language_preference)
        expect(result[1][:name]).to eq(:websearch)
        expect(result[2][:name]).to eq(:stt_diarization_warning)
        expect(result[3][:name]).to eq(:mathjax)
        expect(result[4][:name]).to eq(:system_prompt_suffix)
      end
    end
  end

  describe '.combine' do
    it 'combines base prompt with injections using default separator' do
      base_prompt = 'You are a helpful assistant.'
      injections = [
        { name: :test1, content: 'First injection' },
        { name: :test2, content: 'Second injection' }
      ]

      result = described_class.combine(base_prompt: base_prompt, injections: injections)

      expect(result).to eq("You are a helpful assistant.\n\n---\n\nFirst injection\n\n---\n\nSecond injection")
    end

    it 'combines with custom separator' do
      base_prompt = 'Base prompt'
      injections = [
        { name: :test1, content: 'Injection' }
      ]

      result = described_class.combine(
        base_prompt: base_prompt,
        injections: injections,
        separator: "\n\n"
      )

      expect(result).to eq("Base prompt\n\nInjection")
    end

    it 'handles empty injections' do
      base_prompt = 'Base prompt'
      injections = []

      result = described_class.combine(base_prompt: base_prompt, injections: injections)

      expect(result).to eq('Base prompt')
    end

    it 'skips empty injection content' do
      base_prompt = 'Base prompt'
      injections = [
        { name: :test1, content: 'Valid content' },
        { name: :test2, content: '' },
        { name: :test3, content: '   ' }
      ]

      result = described_class.combine(base_prompt: base_prompt, injections: injections)

      expect(result).to eq("Base prompt\n\n---\n\nValid content")
    end
  end

  describe '.augment' do
    it 'builds and combines in one call for system context' do
      session = {
        runtime_settings: { language: 'ja' }
      }
      options = {
        system_prompt_suffix: 'Be brief.'
      }

      result = described_class.augment(
        base_prompt: 'You are helpful.',
        session: session,
        options: options,
        context: :system
      )

      expect(result).to include('You are helpful.')
      expect(result).to include('Japanese')
      expect(result).to include('Be brief.')
    end

    it 'builds and combines in one call for user context' do
      session = {}
      options = {
        prompt_suffix: 'Please provide sources.'
      }

      result = described_class.augment(
        base_prompt: 'What is AI?',
        session: session,
        options: options,
        context: :user
      )

      expect(result).to eq("What is AI?\n\nPlease provide sources.")
    end
  end

  describe '.augment_user_message' do
    it 'augments user message with prompt_suffix' do
      session = {}
      options = {
        prompt_suffix: 'Be concise.'
      }

      result = described_class.augment_user_message(
        base_message: 'Tell me about Ruby.',
        session: session,
        options: options
      )

      expect(result).to eq("Tell me about Ruby.\n\nBe concise.")
    end

    it 'returns original message when no prompt_suffix' do
      session = {}
      options = {}

      result = described_class.augment_user_message(
        base_message: 'Tell me about Ruby.',
        session: session,
        options: options
      )

      expect(result).to eq('Tell me about Ruby.')
    end
  end

  describe 'error handling' do
    context 'when condition evaluation raises error' do
      it 'skips the rule and continues' do
        # Simulate error by passing nil session when language rule expects hash
        session = nil
        options = {}

        expect {
          result = described_class.build_injections(session: session, options: options)
          expect(result).to be_empty
        }.not_to raise_error
      end
    end
  end
end
