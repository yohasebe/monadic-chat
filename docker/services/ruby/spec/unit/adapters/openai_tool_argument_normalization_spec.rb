require 'spec_helper'
require_relative '../../../lib/monadic/adapters/vendors/openai_helper'

RSpec.describe OpenAIHelper do
  subject(:helper) do
    Class.new do
      include OpenAIHelper
    end.new
  end

  describe '#parse_function_call_arguments' do
    it 'parses tool arguments containing smart quotes' do
      raw_arguments = "{“spec”: {“name”: “ChordAnalyzer”, “features”: [“Key detection”]}}"

      result = helper.send(:parse_function_call_arguments, raw_arguments)

      expect(result).to include('spec')
      expect(result['spec']['name']).to eq('ChordAnalyzer')
      expect(result['spec']['features']).to eq(['Key detection'])
    end

    it 'normalizes common full-width punctuation used in JSON syntax' do
      raw_arguments = "｛\"spec\"：｛\"name\"：＂Demo＂，\"features\"：[＂A＂；＂B＂]｝｝"

      result = helper.send(:parse_function_call_arguments, raw_arguments)

      expect(result).to include('spec')
      expect(result['spec']['features']).to eq(['A', 'B'])
    end

    it 'returns an empty hash when JSON cannot be repaired' do
      result = helper.send(:parse_function_call_arguments, 'not valid json')

      expect(result).to eq({})
    end
  end
end
