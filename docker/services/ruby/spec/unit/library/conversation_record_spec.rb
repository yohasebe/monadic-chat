# frozen_string_literal: true

require_relative '../../../lib/monadic/library/conversation_record'

RSpec.describe Monadic::Library::ConversationRecord do
  let(:at) { Time.utc(2026, 1, 2, 3, 4, 5) }
  let(:messages) do
    [
      { 'role' => 'system', 'text' => 'You are a helper.' },
      { 'role' => 'user', 'text' => "What do my notes say about tides?\nPlease be brief." },
      { 'role' => 'assistant', 'text' => "## Summary\nThey are pulled by the moon.\n```\n# a comment\n```",
        'thinking' => 'private reasoning',
        'workbench_shown' => [{ 'path' => 'conversations/c/workbench/tides.png' }],
        'library_readings' => [{ 'query' => 'tides', 'excerpts' => [{}, {}] }] },
      { 'role' => 'user', 'text' => '   ' }
    ]
  end

  def record
    described_class.of(messages, app_name: 'ChatOpenAI', model: 'gpt-x', at: at)
  end

  it 'is a document named by when it was recorded' do
    expect(record[:name]).to eq('conversation-20260102-030405.md')
  end

  it 'gives the title, app, model and date, then each turn under a heading of its own' do
    content = record[:content]

    expect(content.lines.first).to eq("# What do my notes say about tides?\n")
    expect(content).to include('_App: ChatOpenAI · Model: gpt-x · Recorded: 2026-01-02T03:04:05Z_')
    expect(content.scan(/^## (User|Assistant)$/).flatten).to eq(%w[User Assistant])
  end

  it 'leaves out system messages, thinking and empty turns' do
    content = record[:content]

    expect(content).not_to include('You are a helper.', 'private reasoning')
    expect(content.scan(/^## /).size).to eq(2)
  end

  it "sets a turn's own headings below the turn's, so the turn stays one section, and leaves code as it is" do
    content = record[:content]

    expect(content).to include("##### Summary\n")
    expect(content).to include("```\n# a comment\n```")
    outside_code = content.gsub(/^```\n.*?^```\n/m, '')
    expect(outside_code.scan(/^\#{1,3} (.+)$/).flatten).to eq(['What do my notes say about tides?', 'User', 'Assistant'])
  end

  it 'names the files of a turn as not kept, and what the reply read from the Library' do
    content = record[:content]

    expect(content).to include('_Files: tides.png (not kept in this record)_')
    expect(content).to include('_Read from the Library: "tides" (2 passages)_')
  end

  it 'is nil when no one has said anything yet' do
    expect(described_class.of([{ 'role' => 'system', 'text' => 'x' }])).to be_nil
    expect(described_class.of(nil)).to be_nil
  end
end
