# frozen_string_literal: true

require_relative '../../spec_helper'

# An app written for an earlier version may still set monadic, turn_state
# and context_schema: it loads, and the settings are not kept.
RSpec.describe 'MDSL settings that are no longer used' do
  def load_app(name, top_lines: '', feature_lines: '')
    Dir.mktmpdir do |dir|
      path = File.join(dir, "#{name.downcase}.mdsl")
      File.write(path, <<~MDSL)
        app "#{name}" do
          description "x"
          icon "fa-solid fa-book"
          system_prompt "x"
          llm do
            provider "openai"
          end
          #{top_lines}
          features do
            easy_submit true
            #{feature_lines}
          end
        end
      MDSL
      MonadicDSL::Loader.load(path)
    end
    Object.const_get(name).instance_variable_get(:@settings)
  end

  it 'does not keep monadic or turn_state written in features' do
    settings = load_app('RetiredInFeaturesOpenAI', feature_lines: "monadic true\nturn_state true")

    expect(settings).to include(easy_submit: true)
    expect(settings.keys).not_to include(:monadic, :turn_state)
  end

  it 'does not keep monadic or context_schema written at the top' do
    settings = load_app('RetiredAtTopOpenAI', top_lines: <<~LINES)
      monadic true
      context_schema do
        field :topics, icon: "fa-tags", label: "Topics"
      end
    LINES

    expect(settings).to include(easy_submit: true)
    expect(settings.keys).not_to include(:monadic, :context_schema)
  end
end
