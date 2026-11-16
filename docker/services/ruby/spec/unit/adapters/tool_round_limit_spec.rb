# frozen_string_literal: true

require "spec_helper"
require_relative "../../../lib/monadic/adapters/base_vendor_helper"

# The tool rounds one user turn may take.
RSpec.describe "BaseVendorHelper#tool_round_limit" do
  let(:helper) { Class.new { include BaseVendorHelper }.new }
  let(:session) { { parameters: { "app_name" => "SpecApp" } } }

  def with_settings(settings)
    stub_const("APPS", { "SpecApp" => double("app", settings: settings) })
  end

  it "is the provider's when the app names none" do
    with_settings({})
    expect(helper.tool_round_limit(session, 20)).to eq(20)
  end

  it "is the app's own number" do
    with_settings({ max_tool_rounds: 10 })
    expect(helper.tool_round_limit(session, 20)).to eq(10)
  end

  it "is never more than the provider's" do
    with_settings({ max_tool_rounds: 50 })
    expect(helper.tool_round_limit(session, 20)).to eq(20)
  end

  it "is the provider's for a session with no app" do
    expect(helper.tool_round_limit({}, 20)).to eq(20)
    expect(helper.tool_round_limit(nil, 20)).to eq(20)
  end

  describe "the apps' own limits" do
    apps = File.expand_path("../../../apps", __dir__)
    many_steps = %w[auto_forge jupyter_notebook code_interpreter coding_assistant research_assistant math_tutor
                    mermaid_grapher document_generator novel_writer web_insight live_conversation]
    limits = Dir.glob(File.join(apps, "*", "*.mdsl")).group_by { |file| File.basename(File.dirname(file)) }
                .transform_values { |files| files.map { |file| File.read(file)[/^\s+max_tool_rounds (\d+)$/, 1]&.to_i } }

    it "names every app" do
      expect(limits.keys.size).to be > 20
    end

    limits.each do |app, values|
      if many_steps.include?(app)
        it "leaves #{app}, an app of many steps, at the provider's limit in every variant" do
          expect(values.uniq).to eq([nil])
        end
      else
        it "gives #{app} 10 rounds in every variant" do
          expect(values.uniq).to eq([10])
        end
      end
    end
  end

  it "gives every provider the same cap of tool rounds" do
    caps = Dir[File.expand_path("../../../lib/monadic/adapters/vendors/*_helper.rb", __dir__)].to_h do |path|
      [File.basename(path), File.read(path)[/^\s*MAX_FUNC_CALLS\s*=\s*(\d+)/, 1]]
    end.compact.reject { |_, v| v.nil? }
    expect(caps.size).to be >= 8
    expect(caps.values.uniq).to eq(["20"]), "caps differ: #{caps.inspect}"
  end
end
