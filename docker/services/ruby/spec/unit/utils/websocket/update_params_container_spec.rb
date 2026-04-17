# frozen_string_literal: true

require "spec_helper"

# Regression: verify that handle_ws_update_params triggers on-demand
# container startup when the user selects an app that needs Python,
# Selenium, or PGVector.
#
# Prior to this wiring, ContainerDependencies.ensure_services_for_app was
# only called from the legacy HTTP GET route at monadic.rb `/#{endpoint}`.
# Modern UI flows select apps entirely via WebSocket (UPDATE_PARAMS), so
# the HTTP route was never hit and the on-demand startup never fired.
# The fix adds a background Thread invocation inside the WebSocket
# UPDATE_PARAMS handler so the Python / Selenium / PGVector containers
# start automatically when the user changes app.

RSpec.describe "handle_ws_update_params container startup integration" do
  # Isolate the part of the handler we care about (the app-change guard +
  # helper invocation) so we can test without loading the entire WebSocket
  # stack. Mirrors the real handler logic at misc_handlers.rb L115+.
  def simulate_update_params(session:, incoming:)
    current_app = session[:parameters]["app_name"]
    new_app = incoming["app_name"]&.to_s

    # Merge the incoming params into the session (subset of the real handler)
    session[:parameters].merge!(incoming.transform_keys(&:to_s))

    return nil unless new_app && new_app != current_app

    # In the real handler, ensure_services_async wraps a Thread.new; the
    # helper-level spec (container_dependencies_spec) verifies that the
    # Thread runs. Here we just verify the helper is invoked with the
    # correct app_name.
    Monadic::Utils::ContainerDependencies.ensure_services_async(new_app, reason: "UPDATE_PARAMS")
    new_app
  end

  before do
    require_relative "../../../../lib/monadic/utils/container_dependencies"
  end

  it "triggers ensure_services_async on initial selection" do
    session = { parameters: {} }
    incoming = { "app_name" => "CodeInterpreterOpenAI" }

    expect(Monadic::Utils::ContainerDependencies)
      .to receive(:ensure_services_async)
      .with("CodeInterpreterOpenAI", reason: "UPDATE_PARAMS")

    simulate_update_params(session: session, incoming: incoming)
  end

  it "triggers on app change (ChatOpenAI -> CodeInterpreterOpenAI)" do
    session = { parameters: { "app_name" => "ChatOpenAI" } }
    incoming = { "app_name" => "CodeInterpreterOpenAI" }

    expect(Monadic::Utils::ContainerDependencies)
      .to receive(:ensure_services_async)
      .with("CodeInterpreterOpenAI", reason: "UPDATE_PARAMS")

    simulate_update_params(session: session, incoming: incoming)
  end

  it "does NOT trigger when the same app is re-submitted (no change)" do
    session = { parameters: { "app_name" => "CodeInterpreterOpenAI" } }
    incoming = { "app_name" => "CodeInterpreterOpenAI" }

    expect(Monadic::Utils::ContainerDependencies)
      .not_to receive(:ensure_services_async)

    simulate_update_params(session: session, incoming: incoming)
  end

  it "does NOT trigger when incoming has no app_name" do
    session = { parameters: { "app_name" => "ChatOpenAI" } }
    incoming = { "temperature" => 0.7 }

    expect(Monadic::Utils::ContainerDependencies)
      .not_to receive(:ensure_services_async)

    simulate_update_params(session: session, incoming: incoming)
  end
end
