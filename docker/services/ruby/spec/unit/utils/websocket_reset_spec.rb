# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'WebSocket RESET handler session cleanup' do
  # Test the pattern-based session key cleanup logic
  # that prevents cross-session media leakage

  let(:session) do
    {
      messages: [{ "role" => "user", "text" => "hello" }],
      parameters: { "model" => "gpt-4.1" },
      progressive_tools: ["tool1"],
      monadic_state: { "key" => "value" },
      error: "some error",
      obj: { "data" => true },
      # Provider-specific media keys
      grok_last_image: "image.png",
      gemini3_last_image: "photo.jpg",
      last_video_file: "video.mp4",
      openai_last_image: "diagram.png",
      tool_html_fragments: ["<img src='...'>"],
      # Keys that should NOT be cleaned up
      session_id: "abc-123",
      app_name: "chat"
    }
  end

  def simulate_reset(sess)
    sess[:messages].clear
    sess[:parameters].clear
    sess[:progressive_tools]&.clear
    sess[:monadic_state]&.clear
    sess[:error] = nil
    sess[:obj] = nil
    # Pattern-based media cleanup (mirrors websocket.rb RESET handler)
    sess.keys
      .select { |k| k.is_a?(Symbol) && (k.to_s.match?(/last_image|last_video/) || k == :tool_html_fragments) }
      .each { |k| sess.delete(k) }
  end

  it 'clears messages and parameters' do
    simulate_reset(session)
    expect(session[:messages]).to be_empty
    expect(session[:parameters]).to be_empty
  end

  it 'clears progressive_tools and monadic_state' do
    simulate_reset(session)
    expect(session[:progressive_tools]).to be_empty
    expect(session[:monadic_state]).to be_empty
  end

  it 'nils out error and obj' do
    simulate_reset(session)
    expect(session[:error]).to be_nil
    expect(session[:obj]).to be_nil
  end

  it 'removes keys matching last_image pattern' do
    simulate_reset(session)
    expect(session).not_to have_key(:grok_last_image)
    expect(session).not_to have_key(:gemini3_last_image)
    expect(session).not_to have_key(:openai_last_image)
  end

  it 'removes keys matching last_video pattern' do
    simulate_reset(session)
    expect(session).not_to have_key(:last_video_file)
  end

  it 'removes tool_html_fragments' do
    simulate_reset(session)
    expect(session).not_to have_key(:tool_html_fragments)
  end

  it 'preserves unrelated session keys' do
    simulate_reset(session)
    expect(session[:session_id]).to eq("abc-123")
    expect(session[:app_name]).to eq("chat")
  end

  it 'handles nil progressive_tools and monadic_state' do
    session[:progressive_tools] = nil
    session[:monadic_state] = nil
    expect { simulate_reset(session) }.not_to raise_error
  end

  it 'ignores string keys (only processes symbols)' do
    session["string_last_image"] = "should_stay.png"
    simulate_reset(session)
    expect(session["string_last_image"]).to eq("should_stay.png")
  end

  it 'handles session with no media keys' do
    clean_session = {
      messages: [{ "role" => "user" }],
      parameters: {},
      session_id: "test"
    }
    expect { simulate_reset(clean_session) }.not_to raise_error
    expect(clean_session[:session_id]).to eq("test")
  end
end
