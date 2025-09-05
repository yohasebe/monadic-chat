# frozen_string_literal: true

require_relative '../../spec_helper'
require_relative '../../support/provider_matrix_helper'

# Provider × App の「全ポイント化」に近い最小ケース群。
# 非メディアに限定し、各ポイントで1ケースずつを Provider 横断で実行。

RSpec.describe 'Provider Matrix (all points, non-media)', :api do
  include ProviderMatrixHelper

  SCENARIOS = [
    { app: 'Chat', prompt: 'Say hello briefly.' },
    { app: 'Translate', prompt: 'Translate "Hello" to French. Answer briefly.' },
    { app: 'Mermaid Grapher', prompt: 'Only output mermaid: graph TD; A-->B;' },
    { app: 'Jupyter Notebook', prompt: 'Return a tiny Python snippet to print 2+3.' },
    { app: 'PDF Navigator', prompt: 'Summarize in one short sentence: Monadic Chat provides local AI tools.' },
    { app: 'Research Assistant', prompt: 'In one sentence, explain vector databases.' },
    { app: 'Wikipedia', prompt: 'Give a one-sentence summary of Albert Einstein.' },
    { app: 'Second Opinion', prompt: 'Give a 1-sentence summary of the Eiffel Tower.' },
    { app: 'Monadic Mode', messages: [
        { role: 'user', content: 'My name is Alex. Remember it.' },
        { role: 'user', content: 'What is my name? Answer with one word.' }
      ]
    }
  ]

  it 'runs minimal scenarios across all providers' do
    require_run_api!
    providers_from_env.each do |prov|
      with_provider(prov) do |p|
        SCENARIOS.each do |sc|
          res = sc[:messages] ? p.chat_messages(sc[:messages], app: sc[:app]) : p.chat(sc[:prompt], app: sc[:app])
          assert_valid_text_response(res)
        end
      end
    end
  end
end
