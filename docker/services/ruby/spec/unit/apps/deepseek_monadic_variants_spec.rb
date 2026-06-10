# frozen_string_literal: true

require 'spec_helper'

# Guards the DeepSeek monadic variants added for Translate and Novel Writer.
#
# Why this spec exists: the monadic mechanism on DeepSeek is PROMPT-BASED — it
# appends a JSON-format instruction rather than enforcing a schema via an API
# `response_format` (as OpenAI/Gemini do). These apps therefore depend on the
# model emitting schema-conformant JSON for the {"message", "context"} envelope.
# This spec pins the key wiring so a future edit can't silently drop the
# provider, the monadic flag, the DeepSeek group, or the API-key gate.
#
# Registration/loading and capability-bucket allocation are covered by
# app_loading_real_spec and capability_consistency_spec respectively.
RSpec.describe 'DeepSeek monadic app variants' do
  apps_root = File.expand_path('../../../apps', __dir__)

  {
    'Translate (DeepSeek)' => 'translate/translate_deepseek.mdsl',
    'Novel Writer (DeepSeek)' => 'novel_writer/novel_writer_deepseek.mdsl'
  }.each do |label, rel_path|
    describe label do
      let(:content) { File.read(File.join(apps_root, rel_path)) }

      it 'targets the deepseek provider' do
        expect(content).to match(/provider\s+"deepseek"/)
      end

      it 'enables the monadic mechanism' do
        expect(content).to match(/monadic\s+true/)
      end

      it 'is grouped under DeepSeek' do
        expect(content).to match(/group\s+"DeepSeek"/)
      end

      it 'gates on the DeepSeek API key' do
        expect(content).to match(/disabled\s+!CONFIG\["DEEPSEEK_API_KEY"\]/)
      end

      # Reasoning defaults OFF: with thinking on, DeepSeek's multi-step monadic
      # JSON + session-state tool flow degrades over multiple turns. The user
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
