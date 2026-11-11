# frozen_string_literal: true

require 'spec_helper'
require 'tempfile'

RSpec.describe 'A privacy block in an app definition' do
  def load_app(body)
    Tempfile.create(['privacy_block', '.mdsl']) do |file|
      file.write(body)
      file.flush
      MonadicDSL::Loader.load(file.path)
    end
  end

  let(:definition) do
    <<~MDSL
      app "PrivacyBlockProbeOpenAI" do
        description "probe"
        icon "fa-solid fa-robot"
        system_prompt "probe"
        llm do
          provider "openai"
          model "probe-model"
        end
        features do
          disabled false
        end
        privacy do
          enabled true
          languages ["en"]
        end
      end
    MDSL
  end

  it 'still loads the app, says the block has no effect, and leaves nothing of it in the settings' do
    state = nil
    expect { state = load_app(definition) }.to output(/PrivacyBlockProbeOpenAI.*`privacy do` has no effect/).to_stderr
    expect(state).not_to be_nil
    expect(state.settings).not_to have_key(:privacy)
    expect(state.settings).not_to have_key(:privacy_enabled)
  end
end
