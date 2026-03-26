# frozen_string_literal: true

require "spec_helper"
require_relative "../../../lib/monadic/utils/container_dependencies"

RSpec.describe Monadic::Utils::ContainerDependencies do
  describe ".required_services" do
    context "apps that need no extra containers" do
      it "returns empty set for chat app" do
        settings = { "app_name" => "Chat", "group" => "OpenAI" }
        expect(described_class.required_services(settings)).to eq(Set.new)
      end

      it "returns empty set for translate app" do
        settings = { "app_name" => "Translate", "group" => "Claude" }
        expect(described_class.required_services(settings)).to eq(Set.new)
      end

      it "returns empty set for image_generator app" do
        settings = { "app_name" => "Image Generator", "group" => "OpenAI" }
        expect(described_class.required_services(settings)).to eq(Set.new)
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

    context "apps that need PGVector container" do
      it "detects pgvector need from pdf_vector_storage flag" do
        settings = { "app_name" => "PDF Navigator", "pdf_vector_storage" => true }
        result = described_class.required_services(settings)
        expect(result).to include(:pgvector)
      end

      it "does not require pgvector for pdf_upload (cloud-only)" do
        settings = { "app_name" => "Chat Plus", "pdf_upload" => true }
        result = described_class.required_services(settings)
        expect(result).not_to include(:pgvector)
      end
    end

    context "apps with multiple container needs" do
      it "returns python + selenium for auto_forge" do
        settings = {
          "app_name" => "AutoForge",
          "imported_tool_groups" => [{ "name" => :web_automation, "visibility" => "conditional" }]
        }
        result = described_class.required_services(settings)
        expect(result).to include(:python)
        expect(result).to include(:selenium)
      end

      it "returns python + pgvector for research_assistant with pdf" do
        settings = {
          "app_name" => "Research Assistant",
          "pdf_vector_storage" => true,
          "imported_tool_groups" => [
            { "name" => :python_execution, "visibility" => "always" },
            { "name" => :web_automation, "visibility" => "conditional" }
          ]
        }
        result = described_class.required_services(settings)
        expect(result).to include(:python)
        expect(result).to include(:selenium)
        expect(result).to include(:pgvector)
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

  describe ".service_to_compose_name" do
    it "maps :python to compose service name" do
      expect(described_class.service_to_compose_name(:python)).to eq("python_service")
    end

    it "maps :selenium to compose service name" do
      expect(described_class.service_to_compose_name(:selenium)).to eq("selenium_service")
    end

    it "maps :pgvector to compose service name" do
      expect(described_class.service_to_compose_name(:pgvector)).to eq("pgvector_service")
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

    it "maps :pgvector to container name" do
      expect(described_class.service_to_container_name(:pgvector)).to eq("monadic-chat-pgvector-container")
    end
  end
end
