# frozen_string_literal: true

require "spec_helper"
require_relative "../../../lib/monadic/dsl/loader"

# Tool calls are dispatched with public_send, so every tool an app declares
# must be a public method of the app (request_tool has no method; the
# provider helpers handle it).
APPS_DIR_FOR_TOOL_SPEC = File.expand_path("../../../apps", __dir__)
Dir["#{APPS_DIR_FOR_TOOL_SPEC}/**/*.rb"].sort.each do |f|
  require f
rescue Exception # rubocop:disable Lint/RescueException
  nil
end

RSpec.describe "Declared tools of the built-in apps" do
  def declared_names(klass)
    settings = klass.instance_variable_get(:@settings) || {}
    tools = settings[:tools] || settings["tools"]
    decls = tools.is_a?(Hash) ? Array(tools["function_declarations"] || tools[:function_declarations]) : Array(tools)
    decls.filter_map do |t|
      next unless t.is_a?(Hash)
      t.dig("function", "name") || t.dig(:function, :name) || t["name"] || t[:name]
    end.map(&:to_s)
  end

  it "are public methods of their app" do
    Object.const_set(:APPS, {}) unless Object.const_defined?(:APPS)
    Dir["#{APPS_DIR_FOR_TOOL_SPEC}/**/*.mdsl"].sort.each do |f|
      MonadicDSL::Loader.load(f)
    rescue Exception # rubocop:disable Lint/RescueException
      nil
    end

    builtin = Dir["#{APPS_DIR_FOR_TOOL_SPEC}/**/*.mdsl"].filter_map do |f|
      File.read(f)[/^\s*app\s+"(\w+)"/, 1]
    end.uniq
    checked = 0
    gaps = builtin.filter_map { |n| Object.const_get(n) if Object.const_defined?(n) }.flat_map do |klass|
      names = declared_names(klass) - ["request_tool"]
      next [] if names.empty?
      app = begin
        klass.new
      rescue StandardError
        nil
      end
      next [] unless app
      names.filter_map do |n|
        checked += 1
        "#{klass.name}##{n}" unless app.respond_to?(n)
      end
    end
    expect(checked).to be > 500
    expect(gaps.uniq).to be_empty, "not public: #{gaps.uniq.sort.join(', ')}"
  end
end
