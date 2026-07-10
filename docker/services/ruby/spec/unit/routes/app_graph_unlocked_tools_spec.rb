# frozen_string_literal: true

require 'spec_helper'

# Guards for the dynamic-skill wiring added 2026-07-10:
#  - the /api/app/:name/graph payload must expose the session's dynamically
#    unlocked tools (read from the Rack session shared with the WebSocket
#    handlers) so the Workflow Viewer can mark them;
#  - handle_request_tool must notify the requesting session (NOT broadcast to
#    everyone: unlocks are per-session state, and in server mode other users
#    must not receive them) with a tool_unlocked event.
RSpec.describe 'App graph dynamic-skill wiring' do
  let(:routes_src) do
    File.read(File.expand_path('../../../lib/monadic/routes/api_routes.rb', __dir__))
  end
  let(:ptm_src) do
    File.read(File.expand_path('../../../lib/monadic/utils/progressive_tool_manager.rb', __dir__))
  end

  it 'graph payload includes unlocked_tools sourced from session[:progressive_tools]' do
    block = routes_src[/unlocked_tools:.{0,500}/m]
    expect(block).not_to be_nil
    expect(block).to include('session[:progressive_tools]')
    expect(block).to include('rescue StandardError')
  end

  it 'handle_request_tool emits tool_unlocked to the requesting session first' do
    block = ptm_src[/tool_unlocked.{0,600}/m]
    expect(block).not_to be_nil
    expect(ptm_src).to include('Thread.current[:websocket_session_id]')
    expect(ptm_src).to match(/send_to_session\(payload, ws_sid\)/)
    # Broadcast is only the no-session-id fallback
    expect(ptm_src).to match(/elsif .*broadcast_to_all/)
  end
end
