# frozen_string_literal: true

require 'spec_helper'
require 'monadic/library'

# Verifies that all Knowledge Base MDSL files load cleanly, share the same
# tool surface, and expose the expected provider / group bindings. This is
# unit-level — it does not touch Qdrant or any LLM API.
RSpec.describe 'Knowledge Base app variants' do
  KB_DIR = File.expand_path('../../../apps/knowledge_base', __dir__).freeze

  KB_PROVIDERS = {
    'KnowledgeBaseOpenAI'   => { provider: 'openai',    group: 'OpenAI'    },
    'KnowledgeBaseClaude'   => { provider: 'anthropic', group: 'Anthropic' },
    'KnowledgeBaseGemini'   => { provider: 'gemini',    group: 'Google'    },
    'KnowledgeBaseGrok'     => { provider: 'xai',       group: 'xAI'       },
    'KnowledgeBaseDeepSeek' => { provider: 'deepseek',  group: 'DeepSeek'  },
    'KnowledgeBaseMistral'  => { provider: 'mistral',   group: 'Mistral'   },
    'KnowledgeBaseCohere'   => { provider: 'cohere',    group: 'Cohere'    },
    'KnowledgeBaseOllama'   => { provider: 'ollama',    group: 'Ollama'    }
  }.freeze

  EXPECTED_TOOL_NAMES = %w[
    list_conversations
    search_library
    get_conversation_details
    library_stats
    update_conversation_visibility
    delete_conversation_from_library
    plot_conversation_trajectory
    plot_cross_corpus_trajectory
    import_conversation_from_text
  ].freeze

  it 'has eight MDSL files, one per supported provider (no Perplexity)' do
    files = Dir.glob(File.join(KB_DIR, 'knowledge_base_*.mdsl'))
    expect(files.size).to eq(8)
    perplexity = files.find { |f| File.basename(f).include?('perplexity') }
    expect(perplexity).to be_nil
  end

  it 'exposes the shared SYSTEM_PROMPT via KnowledgeBaseConstants' do
    require File.join(KB_DIR, 'knowledge_base_constants.rb')
    expect(defined?(KnowledgeBaseConstants::SYSTEM_PROMPT)).to be_truthy
    expect(KnowledgeBaseConstants::SYSTEM_PROMPT).to include('Knowledge Base')
    expect(KnowledgeBaseConstants::SYSTEM_PROMPT).to include('library_search')
  end

  it 'exposes shared tool implementations via KnowledgeBaseTools' do
    require File.join(KB_DIR, 'knowledge_base_tools.rb')
    EXPECTED_TOOL_NAMES.each do |tool|
      expect(KnowledgeBaseTools.instance_methods(false)).to include(tool.to_sym),
        "KnowledgeBaseTools is missing #{tool}"
    end
  end

  describe 'each MDSL file' do
    KB_PROVIDERS.each do |class_name, expected|
      it "#{class_name} declares provider=#{expected[:provider]} and group=#{expected[:group]}" do
        path = File.join(KB_DIR, mdsl_for(class_name))
        contents = File.read(path)
        expect(contents).to include("app \"#{class_name}\""),
          "expected #{path} to declare app \"#{class_name}\""
        expect(contents).to include("provider \"#{expected[:provider]}\"")
        expect(contents).to include("group \"#{expected[:group]}\"")
        expect(contents).to include('include_modules "KnowledgeBaseTools"')
        expect(contents).to include('system_prompt KnowledgeBaseConstants::SYSTEM_PROMPT')
      end

      it "#{class_name} defines all expected tools" do
        path = File.join(KB_DIR, mdsl_for(class_name))
        contents = File.read(path)
        EXPECTED_TOOL_NAMES.each do |tool|
          expect(contents).to include("define_tool \"#{tool}\""),
            "expected #{path} to define_tool #{tool}"
        end
      end
    end
  end

  it 'every variant disables itself via missing API key, except Ollama (local)' do
    KB_PROVIDERS.each do |class_name, expected|
      next if expected[:provider] == 'ollama'
      contents = File.read(File.join(KB_DIR, mdsl_for(class_name)))
      expect(contents).to match(/disabled !CONFIG\["[A-Z_]+_API_KEY"\]/),
        "expected #{class_name} to gate on a *_API_KEY config flag"
    end
  end

  def self.mdsl_for(class_name)
    suffix = class_name.sub('KnowledgeBase', '').downcase
    "knowledge_base_#{suffix}.mdsl"
  end

  def mdsl_for(class_name)
    self.class.mdsl_for(class_name)
  end
end
