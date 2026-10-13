# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "json"
require_relative "../../../lib/monadic/json_handler"

# A monadic app's response is the model's text. Undoing extra escaping in it
# must never evaluate it as Ruby, where #{} would run.
RSpec.describe "MonadicChat::JsonHandler#unwrap_from_json" do
  let(:handler) { Object.new.extend(MonadicChat::JsonHandler) }

  it "does not run code the model put in an escaped message" do
    Dir.mktmpdir("unwrap-") do |dir|
      marker = File.join(dir, "ran")
      message = "{\\\"a\\\": \#{File.write(#{marker.dump}, 'x')} }"
      response = { "message" => message, "context" => {} }.to_json

      result = handler.unwrap_from_json(response)

      expect(File.exist?(marker)).to be(false)
      expect(result).to eq("message" => message, "context" => {})
    end
  end
end
