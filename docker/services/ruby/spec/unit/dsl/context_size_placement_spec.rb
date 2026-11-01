# frozen_string_literal: true

require_relative '../../spec_helper'

# context_size is written in the llm block by most apps and in features by
# some; both must reach the app's settings, which the web UI reads.
RSpec.describe 'MDSL context_size placement' do
  def load_app(name, llm_lines: '', feature_lines: '')
    Dir.mktmpdir do |dir|
      path = File.join(dir, "#{name.downcase}.mdsl")
      File.write(path, <<~MDSL)
        app "#{name}" do
          description "x"
          icon "fa-solid fa-book"
          system_prompt "x"
          llm do
            provider "openai"
            #{llm_lines}
          end
          features do
            #{feature_lines}
          end
        end
      MDSL
      MonadicDSL::Loader.load(path)
    end
    Object.const_get(name).instance_variable_get(:@settings)
  end

  it 'takes context_size from the llm block' do
    expect(load_app('CtxLlmOnlyOpenAI', llm_lines: 'context_size 7')[:context_size]).to eq(7)
  end

  it 'takes context_size from features' do
    expect(load_app('CtxFeatureOnlyOpenAI', feature_lines: 'context_size 9')[:context_size]).to eq(9)
  end

  it 'prefers features when both are written' do
    settings = load_app('CtxBothOpenAI', llm_lines: 'context_size 7', feature_lines: 'context_size 9')
    expect(settings[:context_size]).to eq(9)
  end

  it 'leaves context_size unset when neither is written' do
    expect(load_app('CtxNoneOpenAI')[:context_size]).to be_nil
  end
end
