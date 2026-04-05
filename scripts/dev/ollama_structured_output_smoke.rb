#!/usr/bin/env ruby
# frozen_string_literal: true

# Ollama Structured Output Smoke Test
#
# Exercises the end-to-end path that Monadic Chat's Ollama helper uses
# when an app declares `response_format` in its MDSL. This script is
# intentionally standalone — it talks to the helper the same way the
# runtime does, but without WebSocket/Docker plumbing.
#
# Prereq: Ollama must be running locally with at least one model installed
# (default target: qwen3-vl:8b-thinking).
#
# Usage:
#   ruby scripts/dev/ollama_structured_output_smoke.rb
#   ruby scripts/dev/ollama_structured_output_smoke.rb qwen3:4b
#
# Exit status: 0 on success, 1 on failure.

$LOAD_PATH.unshift(File.expand_path("../../docker/services/ruby/lib", __dir__))

require "http"
require "json"

# Minimal stand-ins for Monadic Chat dependencies used by ollama_helper.rb
module DebugHelper; def self.debug(*); end; end
module SystemDefaults; def self.get_default_model(_); nil; end; end
$MODELS = {}
module Monadic
  module Utils
    module ExtraLogger
      def self.log; yield if block_given?; end
      def self.enabled?; false; end
    end
  end
end

require_relative "../../docker/services/ruby/lib/monadic/utils/extra_logger"
require_relative "../../docker/services/ruby/lib/monadic/monadic_performance"
require_relative "../../docker/services/ruby/lib/monadic/utils/function_call_error_handler"
require_relative "../../docker/services/ruby/lib/monadic/utils/system_prompt_injector"
require_relative "../../docker/services/ruby/lib/monadic/adapters/base_vendor_helper"
require_relative "../../docker/services/ruby/lib/monadic/adapters/vendors/ollama_helper"

model = ARGV.first || "qwen3-vl:8b-thinking"
endpoint = OllamaHelper.find_endpoint

unless endpoint
  warn "ERROR: Ollama is not reachable. Start Ollama and retry."
  exit 1
end

puts "Ollama endpoint: #{endpoint}"
puts "Target model:    #{model}"
puts

# Step 1: Verify translate_response_format_for_ollama maps OpenAI-style
# response_format into Ollama's `format` parameter.
openai_style = {
  "type" => "json_schema",
  "json_schema" => {
    "schema" => {
      "type" => "object",
      "properties" => {
        "name" => { "type" => "string" },
        "languages" => { "type" => "array", "items" => { "type" => "string" } }
      },
      "required" => %w[name languages]
    }
  }
}

helper = Class.new { include OllamaHelper }.new
format_param = helper.send(:translate_response_format_for_ollama, openai_style)

unless format_param.is_a?(Hash) && format_param["properties"]&.key?("name")
  warn "ERROR: translate_response_format_for_ollama did not return the expected schema"
  warn "  got: #{format_param.inspect}"
  exit 1
end
puts "✓ translate_response_format_for_ollama produced a valid schema payload"

# Step 2: Send the schema to Ollama and verify the response is valid JSON
# matching the schema.
body = {
  "model" => model,
  "stream" => false,
  "messages" => [
    { "role" => "user",
      "content" => "Return JSON for a person named Ada Lovelace who knows English and Latin." }
  ],
  "format" => format_param
}

res = HTTP.timeout(connect: 5, read: 120).post("#{endpoint}/chat", json: body)

unless res.status.success?
  warn "ERROR: Ollama returned HTTP #{res.status}"
  warn res.body.to_s[0..500]
  exit 1
end

parsed = JSON.parse(res.body)
content = parsed.dig("message", "content")
puts "✓ Ollama returned HTTP 200"
puts "  raw content: #{content.inspect[0..200]}"

begin
  decoded = JSON.parse(content)
rescue JSON::ParserError => e
  warn "ERROR: response content is not valid JSON: #{e.message}"
  exit 1
end

unless decoded.is_a?(Hash) && decoded["name"].is_a?(String) && decoded["languages"].is_a?(Array)
  warn "ERROR: response did not match schema"
  warn "  got: #{decoded.inspect}"
  exit 1
end

puts "✓ Response parsed as JSON matching the schema"
puts "  name:      #{decoded['name']}"
puts "  languages: #{decoded['languages'].inspect}"
puts
puts "SUCCESS: Ollama structured output path is working end-to-end."
