# frozen_string_literal: true

require 'spec_helper'

# An analysis tool group is registered only for a provider that can run it
# itself (Monadic::Utils::ProviderCapabilities). The agents no longer hand the
# work to another provider, so offering the tool elsewhere could only fail.
RSpec.describe 'Analysis tool groups follow the app provider' do
  def tool_names(provider, *groups)
    state = MonadicDSL.app("AnalysisGroups#{provider.capitalize}#{groups.join}") do
      description 'x'
      llm { provider provider }
      tools { import_shared_tools(*groups, visibility: 'always') }
    end
    tools = state.settings[:tools] || state.settings['tools'] || []
    tools = tools['function_declarations'] if tools.is_a?(Hash)
    Array(tools).map do |t|
      f = t[:function] || t['function']
      (f && (f[:name] || f['name'])) || t[:name] || t['name']
    end
  end

  it 'offers image, video and audio analysis to OpenAI' do
    names = tool_names('openai', :image_analysis, :video_analysis, :audio_transcription)
    expect(names).to include('analyze_image', 'analyze_video', 'analyze_audio')
  end

  it 'offers image and video but not audio to Anthropic, which has no speech-to-text' do
    names = tool_names('anthropic', :image_analysis, :video_analysis, :audio_transcription)
    expect(names).to include('analyze_image', 'analyze_video')
    expect(names).not_to include('analyze_audio')
  end

  it 'offers none of them to Ollama' do
    names = tool_names('ollama', :image_analysis, :video_analysis, :audio_transcription)
    expect(names & %w[analyze_image analyze_video analyze_audio]).to be_empty
  end

  it 'leaves other tool groups alone' do
    expect(tool_names('ollama', :file_operations)).not_to be_empty
  end
end
