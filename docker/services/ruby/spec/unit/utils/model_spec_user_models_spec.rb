# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'json'
require_relative '../../../lib/monadic/utils/model_spec'

# The user's models.json is read from the config folder of the mode the
# server runs in, the file the page's model list is made from.
RSpec.describe 'Monadic::Utils::ModelSpec and the user models file' do
  let(:spec) { Monadic::Utils::ModelSpec }

  after { spec.reload! }

  it 'is in the config folder of this mode' do
    allow(Monadic::Utils::Environment).to receive(:config_path).and_return('/somewhere/config')
    expect(spec.user_models_path).to eq('/somewhere/config/models.json')
  end

  it 'gives the adapters the models and properties the file adds' do
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, 'models.json'), JSON.generate('my-local-model' => { 'tool_capability' => false, 'context_window' => [1000, 9000] }))
      allow(Monadic::Utils::Environment).to receive(:config_path).and_return(dir)
      spec.reload!
      expect(spec.model_has_property?('my-local-model', 'context_window')).to be(true)
      expect(spec.get_model_property('my-local-model', 'tool_capability')).to be(false)
    end
  end
end
