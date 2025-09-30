# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../apps/auto_forge/utils/codex_response_analyzer'

RSpec.describe AutoForge::Utils::CodexResponseAnalyzer do
  describe '.analyze_response' do
    let(:existing_content) { '<!DOCTYPE html><html><body>existing</body></html>' }

    it 'detects unified diff patches when existing content is provided' do
      patch = <<~PATCH
        --- a/index.html
        +++ b/index.html
        @@ -1,3 +1,3 @@
        -old line
        +new line
      PATCH

      mode, content = described_class.analyze_response(patch, existing_content: existing_content)

      expect(mode).to eq(:patch)
      expect(content).to include('@@')
    end

    it 'detects full HTML content' do
      html = '<!DOCTYPE html><html><body>Updated</body></html>'

      mode, content = described_class.analyze_response(html)

      expect(mode).to eq(:full)
      expect(content).to include('<!DOCTYPE html>')
    end

    it 'ignores lines starting with plus/minus that are not patches' do
      html = '<html><body>+ Not a patch</body></html>'

      mode, _content = described_class.analyze_response(html, existing_content: existing_content)

      expect(mode).to eq(:full)
    end

    it 'returns :unknown for unsupported content' do
      mode, content = described_class.analyze_response('random text', existing_content: existing_content)

      expect(mode).to eq(:unknown)
      expect(content).to be_nil
    end
  end
end
