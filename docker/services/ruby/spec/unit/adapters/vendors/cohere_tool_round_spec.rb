# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../../lib/monadic/adapters/vendors/cohere_helper'

# configure_cohere_tools must keep tools on tool-round requests (role == "tool")
# and expose web-search tools when the Web Search toggle is on, even for
# progressive-tool apps. Both were dogfood-confirmed against the live Cohere API:
# a replayed assistant tool-call turn with no tools 422s, and a just-unlocked
# skill is only usable if the follow-up request still carries the tool set.
RSpec.describe 'CohereHelper#configure_cohere_tools tool rounds & websearch' do
  subject(:helper) { Class.new { include CohereHelper }.new }

  let(:app_name) { "ChatCohere" }

  def app_double(settings)
    obj = Object.new
    obj.define_singleton_method(:settings) { settings }
    obj.define_singleton_method(:respond_to?) { |m, *| m == :settings || super(m) }
    obj
  end

  def configure(role:, websearch:, settings:, obj: { "model" => "command-a-plus-05-2026" })
    body = {}
    stub_const("APPS", { app_name => app_double(settings) })
    helper.send(:configure_cohere_tools, body, obj, app_name, {}, role, websearch)
    body
  end

  def tool_names(body)
    # App tools use string keys; the shared Tavily definitions use symbol keys.
    # Both serialize fine to JSON — accept either here.
    Array(body["tools"]).map do |t|
      fn = t["function"] || t[:function] || {}
      fn["name"] || fn[:name]
    end
  end

  context 'a plain (non-progressive) app with a declared tool' do
    let(:calc) { { "type" => "function", "function" => { "name" => "calculate", "description" => "calc", "parameters" => { "type" => "object", "properties" => {}, "required" => [] } } } }
    let(:settings) { { "tools" => [calc] } }
    let(:obj) { { "model" => "command-a-plus-05-2026", "tools" => [calc] } }

    it 'keeps tools on a tool-round request (does not skip role == "tool")' do
      body = configure(role: "tool", websearch: false, settings: settings, obj: obj)
      expect(tool_names(body)).to include("calculate")
    end
  end

  context 'a progressive app with Web Search on' do
    let(:settings) do
      {
        "tools" => [],
        "progressive_tools" => { provider: :cohere, all_tool_names: ["request_tool"], always_visible: ["request_tool"], conditional: [] }
      }
    end

    it 'exposes the Tavily web-search tools even in progressive mode' do
      body = configure(role: "user", websearch: true, settings: settings)
      expect(tool_names(body)).to include("tavily_search")
    end

    it 'omits web-search tools when the toggle is off' do
      body = configure(role: "user", websearch: false, settings: settings)
      expect(tool_names(body)).not_to include("tavily_search")
    end
  end
end
