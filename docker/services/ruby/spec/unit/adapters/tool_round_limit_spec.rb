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

  it "is 10 for the conversation apps and the provider's for an app of many steps" do
    apps = File.expand_path("../../../apps", __dir__)
    %w[chat voice_chat language_practice language_practice_plus translate voice_interpreter mail_composer].each do |dir|
      Dir.glob(File.join(apps, dir, "*.mdsl")).each do |file|
        expect(File.read(file)).to match(/^\s+max_tool_rounds 10$/), file
      end
    end
    expect(Dir.glob(File.join(apps, "auto_forge", "*.mdsl")).map { |f| File.read(f) }).to all(satisfy { |t| !t.include?("max_tool_rounds") })
  end
end
