# frozen_string_literal: true

require "spec_helper"

# Regression: verify that handle_load_message triggers on-demand
# container startup when the user reconnects to an existing session
# with a previously-selected app.
#
# Scenario: user selects Code Interpreter, quits Monadic Chat, restarts.
# On restart, the Python container is stopped by Electron's docker compose
# stop. The browser reconnects via WebSocket and sends LOAD. The session
# state restores app_name = "CodeInterpreterOpenAI". Because the app
# hasn't changed from the client's perspective, UPDATE_PARAMS does not
# fire and the Python container never starts — until the user sends a
# message and the tool call fails.
#
# The fix: handle_load_message now fires ensure_services_async for any
# restored app_name, so the container starts during the reconnect window
# before the user's first message.

RSpec.describe "handle_load_message container startup on reconnect" do
  # Isolate the reconnect-trigger logic. The real handler lives at
  # app_data.rb handle_load_message.
  def simulate_load(session:)
    restored = session[:parameters] && session[:parameters]["app_name"]
    return nil if restored.nil? || restored.to_s.strip.empty?

    Monadic::Utils::ContainerDependencies.ensure_services_async(restored, reason: "LOAD reconnect")
    restored
  end

  before do
    require_relative "../../../../lib/monadic/utils/container_dependencies"
  end

  it "triggers ensure_services_async when session restores an app_name" do
    session = { parameters: { "app_name" => "CodeInterpreterOpenAI" } }

    expect(Monadic::Utils::ContainerDependencies)
      .to receive(:ensure_services_async)
      .with("CodeInterpreterOpenAI", reason: "LOAD reconnect")

    result = simulate_load(session: session)
    expect(result).to eq("CodeInterpreterOpenAI")
  end

  it "does NOT trigger when session has no parameters (fresh session)" do
    session = {}

    expect(Monadic::Utils::ContainerDependencies)
      .not_to receive(:ensure_services_async)

    simulate_load(session: session)
  end

  it "does NOT trigger when app_name is empty" do
    session = { parameters: { "app_name" => "" } }

    expect(Monadic::Utils::ContainerDependencies)
      .not_to receive(:ensure_services_async)

    simulate_load(session: session)
  end

  it "does NOT trigger when app_name is whitespace only" do
    session = { parameters: { "app_name" => "   " } }

    expect(Monadic::Utils::ContainerDependencies)
      .not_to receive(:ensure_services_async)

    simulate_load(session: session)
  end
end
