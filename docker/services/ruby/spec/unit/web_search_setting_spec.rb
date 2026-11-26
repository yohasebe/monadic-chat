# frozen_string_literal: true

require 'spec_helper'
require 'monadic/web_search_setting'

RSpec.describe Monadic::WebSearchSetting do
  it 'is on unless the setting is "false"' do
    stub_const('CONFIG', {})
    expect(described_class.on?).to be true
    stub_const('CONFIG', { 'WEB_SEARCH_IN_CHATS' => ' False ' })
    expect(described_class.on?).to be false
  end

  it "lets an app's chats search only when its MDSL says websearch true, and only while the setting is on" do
    stub_const('CONFIG', {})
    app = ->(value) { Struct.new(:settings).new(value.nil? ? {} : { websearch: value }) }
    stub_const('APPS', { 'Yes' => app.call(true), 'Text' => app.call('true'), 'No' => app.call(false), 'Unsaid' => app.call(nil) })

    expect(%w[Yes Text No Unsaid Unknown].map { |n| described_class.allowed?(n) }).to eq([true, true, false, false, false])
    stub_const('CONFIG', { 'WEB_SEARCH_IN_CHATS' => 'false' })
    expect(described_class.allowed?('Yes')).to be false
  end

  it 'leaves web search out at an effort a model says does not go with it' do
    allow(Monadic::Utils::ModelSpec).to receive(:get_model_property).with('m', 'feature_constraints')
      .and_return('reasoning_effort' => { 'incompatible_with' => { 'web_search' => ['minimal'] } })

    expect(described_class.effort_allows?('m', 'minimal')).to be false
    expect(described_class.effort_allows?('m', 'low')).to be true
    expect(described_class.effort_allows?('m', nil)).to be true
  end
end
