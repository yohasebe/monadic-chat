# frozen_string_literal: true

require_relative "../../spec_helper"
require_relative "../../../lib/monadic/shared_tools/registry"

RSpec.describe "MonadicSharedTools::Registry - Planning & Verification" do
  describe "planning tool group" do
    it "is registered in the registry" do
      expect(MonadicSharedTools::Registry.group_exists?(:planning)).to be true
    end

    it "is listed in available groups" do
      expect(MonadicSharedTools::Registry.available_groups).to include(:planning)
    end

    it "references the correct module" do
      expect(MonadicSharedTools::Registry.module_name_for(:planning)).to eq("MonadicSharedTools::Planning")
    end

    it "has a default hint" do
      hint = MonadicSharedTools::Registry.default_hint_for(:planning)
      expect(hint).not_to be_empty
    end

    describe "propose_plan tool" do
      let(:tools) { MonadicSharedTools::Registry.tools_for(:planning) }
      let(:tool) { tools.find { |t| t.name == "propose_plan" } }

      it "defines the propose_plan tool" do
        expect(tool).not_to be_nil
      end

      it "has a description" do
        expect(tool.description).to include("plan")
      end

      it "requires a 'plan' parameter" do
        plan_param = tool.parameters.find { |p| p[:name] == :plan }
        expect(plan_param).not_to be_nil
        expect(plan_param[:type]).to eq("string")
        expect(plan_param[:required]).to be true
      end

      it "requires a 'summary' parameter" do
        summary_param = tool.parameters.find { |p| p[:name] == :summary }
        expect(summary_param).not_to be_nil
        expect(summary_param[:type]).to eq("string")
        expect(summary_param[:required]).to be true
      end
    end
  end

  describe "verification tool group" do
    it "is registered in the registry" do
      expect(MonadicSharedTools::Registry.group_exists?(:verification)).to be true
    end

    it "is listed in available groups" do
      expect(MonadicSharedTools::Registry.available_groups).to include(:verification)
    end

    it "references the correct module" do
      expect(MonadicSharedTools::Registry.module_name_for(:verification)).to eq("MonadicSharedTools::Verification")
    end

    it "has a default hint" do
      hint = MonadicSharedTools::Registry.default_hint_for(:verification)
      expect(hint).not_to be_empty
    end

    describe "report_verification tool" do
      let(:tools) { MonadicSharedTools::Registry.tools_for(:verification) }
      let(:tool) { tools.find { |t| t.name == "report_verification" } }

      it "defines the report_verification tool" do
        expect(tool).not_to be_nil
      end

      it "has a description" do
        expect(tool.description).to include("verification")
      end

      it "requires 'result_summary' parameter" do
        param = tool.parameters.find { |p| p[:name] == :result_summary }
        expect(param).not_to be_nil
        expect(param[:type]).to eq("string")
        expect(param[:required]).to be true
      end

      it "requires 'checks_performed' parameter as array" do
        param = tool.parameters.find { |p| p[:name] == :checks_performed }
        expect(param).not_to be_nil
        expect(param[:type]).to eq("array")
        expect(param[:required]).to be true
      end

      it "requires 'status' parameter" do
        param = tool.parameters.find { |p| p[:name] == :status }
        expect(param).not_to be_nil
        expect(param[:type]).to eq("string")
        expect(param[:required]).to be true
      end

      it "has optional 'issues' parameter" do
        param = tool.parameters.find { |p| p[:name] == :issues }
        expect(param).not_to be_nil
        expect(param[:required]).to be false
      end

      it "has optional 'fixes_applied' parameter" do
        param = tool.parameters.find { |p| p[:name] == :fixes_applied }
        expect(param).not_to be_nil
        expect(param[:required]).to be false
      end
    end
  end

  describe "parallel_dispatch tool group" do
    it "is registered in the registry" do
      expect(MonadicSharedTools::Registry.group_exists?(:parallel_dispatch)).to be true
    end

    it "is listed in available groups" do
      expect(MonadicSharedTools::Registry.available_groups).to include(:parallel_dispatch)
    end

    it "references the correct module" do
      expect(MonadicSharedTools::Registry.module_name_for(:parallel_dispatch)).to eq("MonadicSharedTools::ParallelDispatch")
    end

    it "has a default hint" do
      hint = MonadicSharedTools::Registry.default_hint_for(:parallel_dispatch)
      expect(hint).not_to be_empty
      expect(hint).to include("dispatch_parallel_tasks")
    end

    describe "dispatch_parallel_tasks tool" do
      let(:tools) { MonadicSharedTools::Registry.tools_for(:parallel_dispatch) }
      let(:tool) { tools.find { |t| t.name == "dispatch_parallel_tasks" } }

      it "defines the dispatch_parallel_tasks tool" do
        expect(tool).not_to be_nil
      end

      it "has a description mentioning parallel" do
        expect(tool.description).to include("parallel")
      end

      it "requires a 'tasks' parameter as array" do
        param = tool.parameters.find { |p| p[:name] == :tasks }
        expect(param).not_to be_nil
        expect(param[:type]).to eq("array")
        expect(param[:required]).to be true
      end

      it "has tasks items with object schema" do
        param = tool.parameters.find { |p| p[:name] == :tasks }
        expect(param[:items]).to be_a(Hash)
        expect(param[:items][:type]).to eq("object")
        expect(param[:items][:required]).to include("id", "prompt")
      end

      it "has optional 'timeout' parameter" do
        param = tool.parameters.find { |p| p[:name] == :timeout }
        expect(param).not_to be_nil
        expect(param[:type]).to eq("integer")
        expect(param[:required]).to be false
      end
    end
  end
end
