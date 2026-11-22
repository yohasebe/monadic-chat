# frozen_string_literal: true

require 'spec_helper'

# The DeepSeek variants of Translate and Novel Writer keep their state with
# tools. This spec pins the key wiring: the provider, the state tools, the
# DeepSeek group and the API-key gate.
#
# Registration/loading and capability-bucket allocation are covered by
# app_loading_real_spec and capability_consistency_spec respectively.
RSpec.describe 'DeepSeek app variants that keep state' do
  apps_root = File.expand_path('../../../apps', __dir__)

  {
    'Translate (DeepSeek)' => ['translate/translate_deepseek.mdsl', 'save_translation_context'],
    'Novel Writer (DeepSeek)' => ['novel_writer/novel_writer_deepseek.mdsl', 'save_novel_context']
  }.each do |label, (rel_path, state_tool)|
    describe label do
      let(:content) { File.read(File.join(apps_root, rel_path)) }

      it 'targets the deepseek provider' do
        expect(content).to match(/provider\s+"deepseek"/)
      end

      it 'offers the tool that saves its state' do
        expect(content).to match(/define_tool\s+"#{state_tool}"/)
      end

      it 'is grouped under DeepSeek' do
        expect(content).to match(/group\s+"DeepSeek"/)
      end

      it 'gates on the DeepSeek API key' do
        expect(content).to match(/disabled\s+!CONFIG\["DEEPSEEK_API_KEY"\]/)
      end

      # Reasoning defaults OFF: with thinking on, DeepSeek's multi-step
      # state tool flow degrades over multiple turns. The user
      # can still flip the On/Off toggle in the UI.
      it 'defaults reasoning OFF via reasoning_content "disabled"' do
        expect(content).to match(/reasoning_content\s+"disabled"/)
      end
    end
  end

  it 'defines DeepSeek-backed MonadicApp subclasses' do
    {
      'TranslateDeepSeek' => 'translate/translate_tools.rb',
      'NovelWriterDeepSeek' => 'novel_writer/novel_writer_tools.rb'
    }.each do |klass_name, rel|
      src = File.read(File.join(apps_root, rel))
      expect(src).to match(/class #{klass_name} < MonadicApp/),
                     "#{klass_name} class missing in #{rel}"
      expect(src).to match(/include DeepSeekHelper/)
    end
  end
end
