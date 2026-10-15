# frozen_string_literal: true

require "spec_helper"
require "json"
require_relative "../../lib/monadic/app_extensions"

# The monadic helpers every app gets: wrapping a value with its context, as
# an object and as JSON.
RSpec.describe MonadicChat::AppExtensions do
  let(:host) do
    Class.new do
      include MonadicChat::AppExtensions

      def initialize
        @context = { "test" => true, "count" => 0 }
      end
    end.new
  end

  describe "core wrap / unwrap / transform" do
    it "wraps a value with its context and unwraps it again" do
      wrapped = host.wrap("test value", { "meta" => "data" })
      expect(wrapped.value).to eq("test value")
      expect(host.unwrap(wrapped)).to eq("test value")
    end

    it "transforms the wrapped value" do
      wrapped = host.wrap("test value")
      expect(host.unwrap(host.transform(wrapped) { |v| v.upcase })).to eq("TEST VALUE")
    end
  end

  describe "JSON form" do
    let(:json) { host.wrap_as_json("Hello", { "foo" => "bar" }) }

    it "stores the message and the context" do
      parsed = JSON.parse(json)
      expect(parsed["message"]).to eq("Hello")
      expect(host.unwrap_from_json(json)["context"]["foo"]).to eq("bar")
    end

    it "transforms the context" do
      out = host.transform_json(json) { |ctx| ctx.merge("new_field" => "added") }
      expect(JSON.parse(out)["context"]["new_field"]).to eq("added")
    end
  end

  describe "monadic_unit / monadic_unwrap / monadic_map" do
    it "wraps a message with the app's context" do
      unit = host.monadic_unit("Test message")
      parsed = JSON.parse(unit)
      expect(parsed["message"]).to eq("Test message")
      expect(parsed["context"]).to include("test" => true)
      expect(host.monadic_unwrap(unit)["message"]).to eq("Test message")
    end

    it "maps over the context" do
      mapped = host.monadic_map(host.monadic_unit("m")) { |ctx| ctx.merge("count" => 42) }
      expect(JSON.parse(mapped)["context"]["count"]).to eq(42)
    end
  end
end
