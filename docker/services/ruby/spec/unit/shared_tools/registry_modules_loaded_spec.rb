# frozen_string_literal: true

require "spec_helper"
require_relative "../../../lib/monadic/dsl"

# The DSL includes a shared tool group's module with `include X if defined?(X)`,
# so a module nobody requires is skipped without a word and its tools fail
# when the model calls them. Every registry module must be loaded by dsl.rb.
RSpec.describe MonadicSharedTools::Registry do
  it "has every tool group's module loaded once the DSL is loaded" do
    missing = described_class::TOOL_GROUPS.keys.filter_map do |group|
      name = described_class.module_name_for(group)
      next if name.nil?
      group unless Object.const_defined?(name)
    end
    expect(missing).to be_empty, "modules not loaded for: #{missing.join(', ')}"
  end
end
