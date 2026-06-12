# frozen_string_literal: true

require "spec_helper"
require_relative "../../../lib/monadic/utils/container_dependencies"

RSpec.describe Monadic::Utils::ContainerDependencies do
  describe ".required_services" do
    context "apps with no app-specific extras" do
      it "still returns the base services (qdrant + embeddings)" do
        # Help system depends on these, so they are always required.
        settings = { "app_name" => "Chat", "group" => "OpenAI" }
        expect(described_class.required_services(settings))
          .to eq(Set.new([:qdrant, :embeddings]))
      end

      it "returns base services for translate app" do
        settings = { "app_name" => "Translate", "group" => "Claude" }
        expect(described_class.required_services(settings))
          .to include(:qdrant, :embeddings)
      end

      it "returns base services for image_generator app" do
        settings = { "app_name" => "Image Generator", "group" => "OpenAI" }
        expect(described_class.required_services(settings))
          .to include(:qdrant, :embeddings)
      end
    end

    context "apps that need Python container" do
      it "detects python need from imported_tool_groups with python_execution" do
        settings = {
          "app_name" => "Code Interpreter",
          "imported_tool_groups" => [{ "name" => :python_execution, "visibility" => "always" }]
        }
        result = described_class.required_services(settings)
        expect(result).to include(:python)
      end

      it "detects python need from imported_tool_groups with parallel_python_execution" do
        settings = {
          "app_name" => "Code Interpreter",
          "imported_tool_groups" => [
            { "name" => :python_execution, "visibility" => "always" },
            { "name" => :parallel_python_execution, "visibility" => "always" }
          ]
        }
        result = described_class.required_services(settings)
        expect(result).to include(:python)
      end

      it "detects python need from jupyter flag" do
        settings = { "app_name" => "Jupyter Notebook", "jupyter" => true }
        result = described_class.required_services(settings)
        expect(result).to include(:python)
      end

      it "detects python need from jupyter_operations tool group" do
        settings = {
          "app_name" => "Jupyter Notebook",
          "imported_tool_groups" => [{ "name" => :jupyter_operations, "visibility" => "always" }]
        }
        result = described_class.required_services(settings)
        expect(result).to include(:python)
      end
    end

    context "apps that need Selenium container" do
      it "detects selenium need from web_automation tool group" do
        settings = {
          "app_name" => "Web Insight",
          "imported_tool_groups" => [{ "name" => :web_automation, "visibility" => "always" }]
        }
        result = described_class.required_services(settings)
        expect(result).to include(:selenium)
        expect(result).to include(:python) # Selenium always requires Python
      end
    end

    context "apps with multiple container needs" do
      it "returns python + selenium + base services for auto_forge" do
        settings = {
          "app_name" => "AutoForge",
          "imported_tool_groups" => [{ "name" => :web_automation, "visibility" => "conditional" }]
        }
        result = described_class.required_services(settings)
        expect(result).to include(:python, :selenium, :qdrant, :embeddings)
      end

      it "returns python + selenium + base services for research_assistant" do
        settings = {
          "app_name" => "Research Assistant",
          "imported_tool_groups" => [
            { "name" => :python_execution, "visibility" => "always" },
            { "name" => :web_automation, "visibility" => "conditional" }
          ]
        }
        result = described_class.required_services(settings)
        expect(result).to include(:python, :selenium, :qdrant, :embeddings)
      end
    end

    context "symbol vs string key handling" do
      it "works with symbol keys" do
        settings = { jupyter: true, app_name: "Jupyter Notebook" }
        result = described_class.required_services(settings)
        expect(result).to include(:python)
      end

      it "works with string keys" do
        settings = { "jupyter" => true, "app_name" => "Jupyter Notebook" }
        result = described_class.required_services(settings)
        expect(result).to include(:python)
      end
    end
  end

  describe ".ensure_services_for_app" do
    it "ensures base services even when no app extras are needed" do
      settings = { "app_name" => "Chat" }
      allow(described_class).to receive(:container_running?).and_return(false)
      allow(described_class).to receive(:start_service).and_return(:started)

      result = described_class.ensure_services_for_app(settings)
      expect(result[:started]).to include(:qdrant, :embeddings)
      expect(result[:failed]).to eq([])
    end

    it "returns list of services that were ensured" do
      settings = {
        "app_name" => "Code Interpreter",
        "imported_tool_groups" => [{ "name" => :python_execution, "visibility" => "always" }]
      }
      allow(described_class).to receive(:container_running?).and_return(false)
      allow(described_class).to receive(:start_service).and_return(:started)

      result = described_class.ensure_services_for_app(settings)
      expect(result[:started]).to include(:python, :qdrant, :embeddings)
    end

    it "skips services that are already running" do
      settings = {
        "app_name" => "Code Interpreter",
        "imported_tool_groups" => [{ "name" => :python_execution, "visibility" => "always" }]
      }
      allow(described_class).to receive(:container_running?).and_return(true)
      allow(described_class).to receive(:start_service) # stub to verify not called

      result = described_class.ensure_services_for_app(settings)
      expect(result).to eq({ started: [], failed: [] })
      expect(described_class).not_to have_received(:start_service)
    end

    it "starts both Python and Selenium for web_automation apps" do
      settings = {
        "app_name" => "Web Insight",
        "imported_tool_groups" => [{ "name" => :web_automation, "visibility" => "always" }]
      }
      allow(described_class).to receive(:container_running?).and_return(false)
      allow(described_class).to receive(:start_service).and_return(:started)

      result = described_class.ensure_services_for_app(settings)
      expect(result[:started]).to include(:python, :selenium)
    end

    it "reports failed services in :failed instead of dropping them silently" do
      settings = {
        "app_name" => "Code Interpreter",
        "imported_tool_groups" => [{ "name" => :python_execution, "visibility" => "always" }]
      }
      allow(described_class).to receive(:container_running?).and_return(false)
      allow(described_class).to receive(:start_service) do |service|
        service == :python ? :not_built : :started
      end

      result = described_class.ensure_services_for_app(settings)
      expect(result[:failed]).to eq([:python])
      expect(result[:started]).to include(:qdrant, :embeddings)
    end

    it "treats disabled services as neither started nor failed" do
      settings = { "app_name" => "Chat", "privacy_enabled" => true }
      allow(described_class).to receive(:container_running?).and_return(false)
      allow(described_class).to receive(:start_service) do |service|
        service == :privacy ? :disabled : :started
      end

      result = described_class.ensure_services_for_app(settings)
      expect(result[:started]).not_to include(:privacy)
      expect(result[:failed]).not_to include(:privacy)
    end
  end

  # Every ensure-service outcome must be handled explicitly. The original
  # extractor bug (beta.16) survived because non-matching statuses fell
  # through to a broken `docker compose` fallback and the result was
  # discarded — a dependency container could fail to start with zero trace.
  describe ".start_service status handling" do
    before do
      allow(described_class).to receive(:find_monadic_sh).and_return("/fake/monadic.sh")
      allow(Monadic::Utils::DegradationNotifier).to receive(:report)
    end

    def stub_ensure_service_output(output)
      allow(described_class).to receive(:`).and_return(output)
    end

    it "returns :started when STARTED and the container is verifiably up" do
      stub_ensure_service_output("STARTED\n")
      allow(described_class).to receive(:container_running?).with(:python).and_return(true)
      expect(described_class.start_service(:python)).to eq(:started)
      expect(Monadic::Utils::DegradationNotifier).not_to have_received(:report)
    end

    it "returns :failed and reports when STARTED but the container is not up" do
      stub_ensure_service_output("STARTED\n")
      allow(described_class).to receive(:container_running?).with(:python).and_return(false)
      expect(described_class.start_service(:python)).to eq(:failed)
      expect(Monadic::Utils::DegradationNotifier).to have_received(:report)
        .with(hash_including(component: "container:python", severity: :error))
    end

    it "returns :already_running without reporting" do
      stub_ensure_service_output("ALREADY_RUNNING")
      expect(described_class.start_service(:selenium)).to eq(:already_running)
      expect(Monadic::Utils::DegradationNotifier).not_to have_received(:report)
    end

    it "returns :disabled for *_DISABLED without reporting (user opt-out is not a failure)" do
      stub_ensure_service_output("PRIVACY_DISABLED")
      expect(described_class.start_service(:privacy)).to eq(:disabled)
      expect(Monadic::Utils::DegradationNotifier).not_to have_received(:report)
    end

    it "returns :not_built and reports for *_NOT_BUILT" do
      stub_ensure_service_output("EMBEDDINGS_NOT_BUILT")
      expect(described_class.start_service(:embeddings)).to eq(:not_built)
      expect(Monadic::Utils::DegradationNotifier).to have_received(:report)
        .with(hash_including(component: "container:embeddings", severity: :error))
    end

    it "returns :failed and reports for unrecognized output" do
      stub_ensure_service_output("something unexpected")
      expect(described_class.start_service(:python)).to eq(:failed)
      expect(Monadic::Utils::DegradationNotifier).to have_received(:report)
        .with(hash_including(component: "container:python"))
    end

    it "returns :failed and reports for empty output" do
      stub_ensure_service_output("")
      expect(described_class.start_service(:python)).to eq(:failed)
      expect(Monadic::Utils::DegradationNotifier).to have_received(:report)
    end

    it "returns :failed and reports when monadic.sh cannot be located (no silent compose fallback)" do
      allow(described_class).to receive(:find_monadic_sh).and_return(nil)
      expect(described_class).not_to receive(:`)
      expect(described_class.start_service(:python)).to eq(:failed)
      expect(Monadic::Utils::DegradationNotifier).to have_received(:report)
        .with(hash_including(component: "container:python", severity: :error))
    end

    it "returns :failed for unknown services" do
      expect(described_class.start_service(:bogus)).to eq(:failed)
    end
  end

  describe ".container_running?" do
    it "checks Docker container status" do
      # This test verifies the method exists and returns a boolean
      result = described_class.container_running?(:python)
      expect([true, false]).to include(result)
    end
  end

  describe ".service_to_compose_name" do
    it "maps :python to compose service name" do
      expect(described_class.service_to_compose_name(:python)).to eq("python_service")
    end

    it "maps :selenium to compose service name" do
      expect(described_class.service_to_compose_name(:selenium)).to eq("selenium_service")
    end

    it "maps :qdrant to compose service name" do
      expect(described_class.service_to_compose_name(:qdrant)).to eq("qdrant_service")
    end

    it "maps :embeddings to compose service name" do
      expect(described_class.service_to_compose_name(:embeddings)).to eq("embeddings_service")
    end

    it "returns nil for unknown service" do
      expect(described_class.service_to_compose_name(:unknown)).to be_nil
    end
  end

  describe ".service_to_container_name" do
    it "maps :python to container name" do
      expect(described_class.service_to_container_name(:python)).to eq("monadic-chat-python-container")
    end

    it "maps :selenium to container name" do
      expect(described_class.service_to_container_name(:selenium)).to eq("monadic-chat-selenium-container")
    end

    it "maps :qdrant to container name" do
      expect(described_class.service_to_container_name(:qdrant)).to eq("monadic-chat-qdrant-container")
    end

    it "maps :embeddings to container name" do
      expect(described_class.service_to_container_name(:embeddings)).to eq("monadic-chat-embeddings-container")
    end
  end

  # Regression: path resolution for monadic.sh in dev layout (2026-04).
  # Prior to the fix, the candidate paths in find_monadic_sh resolved to
  # `docker/services/monadic.sh` and `docker/docker/monadic.sh` — neither
  # file exists. As a result, on-demand container startup fell through to
  # the `docker compose` fallback which also failed in packaged environments,
  # and the Python container never auto-started when the user selected
  # Code Interpreter / Jupyter Notebook apps.
  describe ".find_monadic_sh" do
    it "resolves to the real docker/monadic.sh in the dev repository" do
      found = described_class.find_monadic_sh
      expect(found).not_to be_nil,
        "find_monadic_sh returned nil — monadic.sh cannot be located from container_dependencies.rb"
      expect(File.exist?(found)).to be true
      expect(File.basename(found)).to eq("monadic.sh")
    end

    it "finds a file whose parent directory is `docker`" do
      # Sanity: the found file must live under the project's `docker/` folder,
      # not a spurious `docker/docker/` or similar doubled path.
      found = described_class.find_monadic_sh
      expect(File.basename(File.dirname(found))).to eq("docker")
    end
  end

  # ensure_services_async is the fire-and-forget wrapper called by three
  # call sites: UPDATE_PARAMS (handle_ws_update_params), LOAD reconnect
  # (handle_load_message), and the legacy bookmark route (monadic.rb).
  # These tests lock down the contract so drift between call sites can't
  # reintroduce the "wire is there but never fires" class of bug.
  describe ".ensure_services_async" do
    before do
      # APPS is the global module-level registry of apps. Stub it here so the
      # helper's lookup path is exercised without loading the full app set.
      code_interpreter_settings = {
        imported_tool_groups: [{ name: :python_execution, visibility: "always" }]
      }
      stub_const("APPS", {
        "CodeInterpreterOpenAI" => Struct.new(:settings).new(code_interpreter_settings)
      })
      # Avoid actually starting containers during the test.
      allow(described_class).to receive(:ensure_services_for_app)
        .and_return({ started: [], failed: [] })
      # Run the spawned thread inline so expectations are synchronous.
      allow(Thread).to receive(:new) { |&blk| blk.call; Thread.current }
    end

    it "returns true and calls ensure_services_for_app when app exists" do
      expect(described_class).to receive(:ensure_services_for_app)
        .with(hash_including(imported_tool_groups: an_instance_of(Array)))
      result = described_class.ensure_services_async("CodeInterpreterOpenAI", reason: "test")
      expect(result).to be true
    end

    it "returns false and does nothing when app_name is nil" do
      expect(described_class).not_to receive(:ensure_services_for_app)
      expect(described_class.ensure_services_async(nil)).to be false
    end

    it "returns false and does nothing when app_name is empty string" do
      expect(described_class).not_to receive(:ensure_services_for_app)
      expect(described_class.ensure_services_async("")).to be false
      expect(described_class.ensure_services_async("   ")).to be false
    end

    it "returns false when the app is not in APPS" do
      expect(described_class).not_to receive(:ensure_services_for_app)
      expect(described_class.ensure_services_async("NonexistentApp")).to be false
    end

    it "swallows errors from ensure_services_for_app without raising" do
      allow(described_class).to receive(:ensure_services_for_app).and_raise("boom")
      expect {
        described_class.ensure_services_async("CodeInterpreterOpenAI", reason: "test-fail")
      }.not_to raise_error
    end
  end
end
