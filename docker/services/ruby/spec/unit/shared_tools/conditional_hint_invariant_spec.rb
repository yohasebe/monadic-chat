# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../lib/monadic/shared_tools/registry'

# The skill menu injected into request_tool's description is built from each
# conditional group's default_hint. A hint that tells the model to "Call
# <skill>" WITHOUT going through request_tool leads strict providers (e.g.
# Cohere command-a-plus) to call the still-locked skill directly, which the API
# rejects with 422 "invalid tool generation". Every conditional group's hint
# must route the model through request_tool with the group key.
RSpec.describe 'Conditional tool-group unlock hints' do
  Registry = MonadicSharedTools::Registry

  Registry.available_groups.each do |group|
    next unless Registry.visibility_for(group) == 'conditional'

    hint = Registry.default_hint_for(group)
    next if hint.nil? || hint.empty?

    it "#{group}: default_hint routes unlocking through request_tool" do
      expect(hint).to include('request_tool'),
        "conditional group #{group.inspect} hint must instruct request_tool(...) " \
        "so the model unlocks the group instead of calling the locked skill directly. Got: #{hint.inspect}"
    end
  end
end
