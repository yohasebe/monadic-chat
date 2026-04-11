# frozen_string_literal: true

require 'spec_helper'
require 'set'
require_relative '../../../lib/monadic/utils/websocket/html_handler'

# Focused tests for WebSocketHelper#dedupe_tool_html_fragments.
#
# Background: `enrich_with_images` (python_execution.rb) automatically appends
# `<div class="generated_image"><img src="/data/...">` HTML fragments to
# session[:tool_html_fragments] for any PNG/JPG/etc. found in run_code output.
# Meanwhile, Code Interpreter system prompts ALSO instruct the LLM to write
# <img> tags for displayed images. When the LLM doesn't obey run_code's
# "Do NOT include <img> tags" guardrail (app.rb L597), both the LLM-written
# tag and the server-appended gallery fragment render, resulting in duplicate
# chart display. This helper removes gallery fragments whose images are
# already in the LLM text.
RSpec.describe WebSocketHelper, '#dedupe_tool_html_fragments' do
  # Minimal host class to exercise the private helper.
  let(:host) do
    Class.new do
      include WebSocketHelper
      public :dedupe_tool_html_fragments
    end.new
  end

  let(:gallery_fragment_for) do
    ->(basename) { %Q(<div class="generated_image"><img src="/data/#{basename}" /></div>) }
  end

  it 'drops a gallery fragment when the LLM already embedded the same image' do
    llm_text = %Q(Here is the chart: <img src="/data/sales_chart.png" />)
    fragments = [gallery_fragment_for.call('sales_chart.png')]
    expect(host.dedupe_tool_html_fragments(llm_text, fragments)).to eq([])
  end

  it 'keeps gallery fragments when the LLM text has no image tags' do
    llm_text = 'I have plotted the data. See below.'
    fragments = [gallery_fragment_for.call('sales_chart.png')]
    expect(host.dedupe_tool_html_fragments(llm_text, fragments)).to eq(fragments)
  end

  it 'keeps gallery fragments for images the LLM did not embed' do
    llm_text = %Q(<img src="/data/one.png" />)
    fragments = [
      gallery_fragment_for.call('one.png'),      # duplicate
      gallery_fragment_for.call('two.png')       # unique
    ]
    result = host.dedupe_tool_html_fragments(llm_text, fragments)
    expect(result).to eq([gallery_fragment_for.call('two.png')])
  end

  it 'is case-insensitive for filename matching' do
    llm_text = %Q(<img src="/data/Chart.PNG" />)
    fragments = [gallery_fragment_for.call('chart.png')]
    expect(host.dedupe_tool_html_fragments(llm_text, fragments)).to eq([])
  end

  it 'ignores non-gallery fragments (e.g. ABC notation HTML from Music Lab)' do
    llm_text = %Q(<img src="/data/score.png" />)
    abc_fragment = %Q(<div class="abc-notation" data-abc="X:1\nT:Test"></div>)
    fragments = [abc_fragment]
    expect(host.dedupe_tool_html_fragments(llm_text, fragments)).to eq(fragments)
  end

  it 'keeps a multi-image fragment when only some images are embedded' do
    # A fragment containing two images, one of which the LLM embedded.
    # Dropping the whole fragment would lose the unique image, so keep it.
    llm_text = %Q(<img src="/data/one.png" />)
    multi_fragment = %Q(<div class="generated_image"><img src="/data/one.png" /></div>) +
                     %Q(\n<div class="generated_image"><img src="/data/two.png" /></div>)
    result = host.dedupe_tool_html_fragments(llm_text, [multi_fragment])
    expect(result).to eq([multi_fragment])
  end

  it 'handles empty fragments array' do
    llm_text = %Q(<img src="/data/chart.png" />)
    expect(host.dedupe_tool_html_fragments(llm_text, [])).to eq([])
  end

  it 'handles empty text' do
    fragments = [gallery_fragment_for.call('chart.png')]
    expect(host.dedupe_tool_html_fragments('', fragments)).to eq(fragments)
  end
end
