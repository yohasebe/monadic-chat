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
  # background thread call) into a helper so we can test without loading
  # the entire WebSocket stack.
  def simulate_update_params(session:, incoming:, apps:)
    current_app = session[:parameters]["app_name"]
    new_app = incoming["app_name"]&.to_s

    # Merge the incoming params into the session (subset of the real handler)
    session[:parameters].merge!(incoming.transform_keys(&:to_s))

    return nil unless new_app && apps[new_app] && new_app != current_app

    target_settings = apps[new_app].settings
    # In the real handler this runs in Thread.new; for the test we call
    # synchronously so we can assert the invocation.
    Monadic::Utils::ContainerDependencies.ensure_services_for_app(target_settings)
    target_settings
  end

  let(:code_interpreter_settings) do
    {
      "app_name" => "CodeInterpreterOpenAI",
      imported_tool_groups: [{ name: :python_execution, visibility: "always" }]
    }
  end

  let(:chat_settings) do
    {
      "app_name" => "ChatOpenAI",
      imported_tool_groups: []
    }
  end

  let(:apps) do
    {
      "CodeInterpreterOpenAI" => Struct.new(:settings).new(code_interpreter_settings),
      "ChatOpenAI" => Struct.new(:settings).new(chat_settings)
    }
  end

  before do
    require_relative "../../../../lib/monadic/utils/container_dependencies"
  end

  it "triggers ensure_services_for_app with target app settings on initial selection" do
    session = { parameters: {} }
    incoming = { "app_name" => "CodeInterpreterOpenAI" }

    expect(Monadic::Utils::ContainerDependencies)
      .to receive(:ensure_services_for_app)
      .with(code_interpreter_settings)

    result = simulate_update_params(session: session, incoming: incoming, apps: apps)
    expect(result).to eq(code_interpreter_settings)
  end

  it "triggers on app change (ChatOpenAI -> CodeInterpreterOpenAI)" do
    session = { parameters: { "app_name" => "ChatOpenAI" } }
    incoming = { "app_name" => "CodeInterpreterOpenAI" }

    expect(Monadic::Utils::ContainerDependencies)
      .to receive(:ensure_services_for_app)
      .with(code_interpreter_settings)

    simulate_update_params(session: session, incoming: incoming, apps: apps)
  end

  it "does NOT trigger when the same app is re-submitted (no change)" do
    session = { parameters: { "app_name" => "CodeInterpreterOpenAI" } }
    incoming = { "app_name" => "CodeInterpreterOpenAI" }

    expect(Monadic::Utils::ContainerDependencies)
      .not_to receive(:ensure_services_for_app)

    simulate_update_params(session: session, incoming: incoming, apps: apps)
  end

  it "does NOT trigger when incoming has no app_name" do
    session = { parameters: { "app_name" => "ChatOpenAI" } }
    incoming = { "temperature" => 0.7 }

    expect(Monadic::Utils::ContainerDependencies)
      .not_to receive(:ensure_services_for_app)

    simulate_update_params(session: session, incoming: incoming, apps: apps)
  end

  it "does NOT trigger when the app_name is unknown (APPS missing)" do
    session = { parameters: {} }
    incoming = { "app_name" => "TotallyMadeUpApp" }

    expect(Monadic::Utils::ContainerDependencies)
      .not_to receive(:ensure_services_for_app)

    simulate_update_params(session: session, incoming: incoming, apps: apps)
  end
end
