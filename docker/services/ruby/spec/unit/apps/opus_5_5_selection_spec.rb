# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../lib/monadic/dsl/loader'
require_relative '../../../apps/math_tutor/math_tutor_constants'

RSpec.describe 'Opus 5.5 app selections' do
  {
    'chat_plus' => ['ChatPlusClaude', :choice],
    'language_practice_plus' => ['LanguagePracticePlusClaude', :choice],
    'coding_assistant' => ['CodingAssistantClaude', :advisor],
    'code_interpreter' => ['CodeInterpreterClaude', :advisor],
    'jupyter_notebook' => ['JupyterNotebookClaude', :advisor],
    'auto_forge' => ['AutoForgeClaude', :advisor],
    'math_tutor' => ['MathTutorClaude', :primary],
    'concept_visualizer' => ['ConceptVisualizerClaude', :primary],
    'drawio_grapher' => ['DrawIOGrapherClaude', :primary]
  }.each do |app, (class_name, selection)|
    it "loads #{app} with the current Opus #{selection}" do
      path = File.expand_path("../../../apps/#{app}/#{app}_claude.mdsl", __dir__)
      MonadicDSL::Loader.load(path)
      settings = Object.const_get(class_name).instance_variable_get(:@settings)
      if selection == :advisor
        advisor = settings[:advisor_tool] || settings['advisor_tool']
        expect(advisor[:model] || advisor['model']).to eq('claude-opus-5-5')
        expect(settings[:model] || settings['model']).to eq('claude-sonnet-5')
      elsif selection == :choice
        expect(settings[:models] || settings['models'] || settings[:model] || settings['model']).to include('claude-opus-5-5')
      else
        expect(settings[:model] || settings['model']).to eq('claude-opus-5-5')
      end
    end
  end
end
