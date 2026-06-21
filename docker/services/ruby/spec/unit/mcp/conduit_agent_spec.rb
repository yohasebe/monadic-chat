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

  describe ".assemble_tools" do
    it "builds OpenAI-style function defs and resolves executor modules" do
      defs, modules = described_class.assemble_tools(%w[web_search_tools])
      expect(defs).to be_an(Array).and(be_any)
      first = defs.first
      expect(first["type"]).to eq("function")
      expect(first["function"]).to include("name", "description", "parameters")
      expect(defs.map { |d| d["function"]["name"] }).to include("search_web")
      expect(modules).to include(MonadicSharedTools::WebSearchTools)
    end
  end
end
