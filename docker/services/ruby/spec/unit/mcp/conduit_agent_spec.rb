# frozen_string_literal: true

require "spec_helper"
require_relative "../../../lib/monadic/mcp/conduit_agent"

RSpec.describe Monadic::MCP::ConduitAgent do
  describe ".normalize_groups" do
    it "defaults to web_search_tools when none given" do
      expect(described_class.normalize_groups(nil)).to eq(%w[web_search_tools])
      expect(described_class.normalize_groups([])).to eq(%w[web_search_tools])
    end

    it "accepts allowed read-only groups and de-dups" do
      expect(described_class.normalize_groups(%w[web_search_tools file_reading web_search_tools]))
        .to eq(%w[web_search_tools file_reading])
    end

    it "rejects disallowed (execution/container) groups" do
      expect { described_class.normalize_groups(%w[python_execution]) }
        .to raise_error(ArgumentError, /not permitted/)
      expect { described_class.normalize_groups(%w[web_automation]) }
        .to raise_error(ArgumentError, /not permitted/)
    end

    it "rejects unknown groups" do
      expect { described_class.normalize_groups(%w[totally_made_up]) }
        .to raise_error(ArgumentError, /not permitted|unknown/)
    end
  end

  describe ".allowed_groups" do
    it "is read-only and excludes code/file/container power" do
      excluded = %w[python_execution file_operations web_automation jupyter_operations
                    app_creation parallel_python_execution]
      expect(described_class.allowed_groups & excluded).to be_empty
      expect(described_class.allowed_groups).to include("web_search_tools")
    end
  end

  describe ".build_agent_app" do
    after { described_class.send(:remove_app_class, @app_state.name) if @app_state }

    it "builds a real app via the DSL with provider-formatted tools (no hand conversion)" do
      @app_state = described_class.send(:build_agent_app, "openai", "gpt-5.4", %w[file_reading])
      klass = Object.const_get(@app_state.name)
      settings = ActiveSupport::HashWithIndifferentAccess.new(klass.instance_variable_get(:@settings) || {})
      names = Array(settings["tools"]).map { |t| t.dig("function", "name") }
      # The DSL imported the file_reading group and formatted it as function tools.
      expect(names).to include("fetch_text_from_file")
      expect(settings["websearch"]).to be_nil.or be(false)
    end

    it "enables web search via the websearch feature" do
      @app_state = described_class.send(:build_agent_app, "openai", "gpt-5.4", %w[web_search_tools])
      settings = ActiveSupport::HashWithIndifferentAccess.new(
        Object.const_get(@app_state.name).instance_variable_get(:@settings) || {}
      )
      expect(settings["websearch"]).to be true
    end
  end
end
