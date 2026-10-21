# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../lib/monadic/adapters/base_vendor_helper'

# The user message of a turn is recorded once, when the server accepts the
# send; the provider helper adds its fields to that message. It is found by
# the request the answer runs under, so a text sent before does not catch
# the new turn's fields.
RSpec.describe BaseVendorHelper, '#record_user_turn!' do
  subject(:helper) { Class.new { include BaseVendorHelper }.new }

  def turn(text, mid: 'h1', images: nil)
    content = { 'mid' => mid, 'role' => 'user', 'text' => text, 'html' => "<p>#{text}</p>" }
    content['images'] = images if images
    { 'type' => 'user', 'content' => content }
  end

  def accepted(text, request_id, attachments: nil)
    message = { 'mid' => 's', 'request_id' => request_id, 'role' => 'user', 'text' => text, 'active' => true }
    message['attachments'] = attachments if attachments
    message
  end

  let(:refs) { [{ 'attachment_id' => 'a_0123456789abcdef', 'role' => 'input', 'purpose' => 'video', 'display_name' => 'clip.mp4' }] }

  it 'adds the fields to the message of this request, not to an earlier one with the same text' do
    earlier = accepted('Describe it', 'q_earlier')
    current = accepted('Describe it', 'q_current', attachments: refs)
    session = { messages: [earlier, { 'role' => 'assistant', 'text' => 'A clip.' }, current] }
    context = Monadic::Workspace::RequestContext.new(chat_id: 'c_x', request_id: 'q_current')

    Monadic::Workspace::RequestContext.with(context) { helper.record_user_turn!(session, turn('Describe it', images: [{ 'title' => 'x.png' }])) }

    expect(session[:messages].size).to eq(3)
    expect(current['html']).to eq('<p>Describe it</p>')
    expect(current['images']).to eq([{ 'title' => 'x.png' }])
    expect(current['attachments']).to eq(refs)
    expect(earlier).not_to have_key('html')
  end

  it 'shows the page the attachments of the message' do
    session = { messages: [accepted('Look', 'q_1', attachments: refs)] }
    shown = []
    context = Monadic::Workspace::RequestContext.new(chat_id: 'c_x', request_id: 'q_1')

    Monadic::Workspace::RequestContext.with(context) { helper.record_user_turn!(session, turn('Look')) { |res| shown << res } }

    expect(shown.size).to eq(1)
    expect(shown.first['content']['attachments']).to eq(refs)
  end

  it 'shows the message only once the session holds it as shown' do
    session = { messages: [accepted('Look', 'q_1')] }
    held = nil
    context = Monadic::Workspace::RequestContext.new(chat_id: 'c_x', request_id: 'q_1')

    Monadic::Workspace::RequestContext.with(context) do
      helper.record_user_turn!(session, turn('Look', mid: 'h9')) { |res| held = session[:messages].map { |m| m['mid'] }.include?(res['content']['mid']) }
    end

    expect(held).to be(true)
  end

  it 'adds the message, under the request, when no accepted message has it; once' do
    session = { messages: [accepted('Hello', 'q_other')] }
    context = Monadic::Workspace::RequestContext.new(chat_id: 'c_x', request_id: 'q_new')

    Monadic::Workspace::RequestContext.with(context) do
      helper.record_user_turn!(session, turn('Hello'))
      helper.record_user_turn!(session, turn('Hello', mid: 'h2'))
    end

    expect(session[:messages].size).to eq(2)
    expect(session[:messages].last['request_id']).to eq('q_new')
    expect(session[:messages].last['mid']).to eq('h2')
  end

  it 'without a request, takes the last message when it has the same text, and adds one otherwise' do
    first = accepted('Same', 'q_a')
    session = { messages: [first, { 'role' => 'assistant', 'text' => 'ok' }, accepted('Same', 'q_b')] }

    helper.record_user_turn!(session, turn('Same'))
    expect(session[:messages].size).to eq(3)
    expect(session[:messages].last['html']).to eq('<p>Same</p>')
    expect(first).not_to have_key('html')

    helper.record_user_turn!(session, turn('Different', mid: 'h2'))
    expect(session[:messages].size).to eq(4)
  end

  # Every provider helper goes through record_user_turn!; none looks a user
  # message up by its text, and none adds the turn's message by itself.
  describe 'provider helpers' do
    vendors = Dir[File.expand_path('../../../lib/monadic/adapters/vendors/*_helper.rb', __dir__)]
              .map { |f| File.basename(f, '_helper.rb') } - ['tavily']

    it 'covers the chat providers' do
      expect(vendors).to include('openai', 'claude', 'gemini', 'grok', 'deepseek', 'cohere', 'mistral', 'ollama')
    end

    vendors.each do |vendor|
      it "#{vendor} records the user turn through record_user_turn!" do
        source = File.read(File.expand_path("../../../lib/monadic/adapters/vendors/#{vendor}_helper.rb", __dir__))
        expect(source.scan('record_user_turn!(session, res, &block)').size).to eq(1)
        expect(source).not_to match(/m\["text"\]\s*==/)
      end
    end
  end
end
