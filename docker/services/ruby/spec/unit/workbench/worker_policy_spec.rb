# frozen_string_literal: true

require_relative "../../spec_helper"
require_relative "../../../lib/monadic/workbench/worker_policy"

RSpec.describe Monadic::Workbench::WorkerPolicy do
  let(:inner) { ->(_env) { [200, { "content-type" => "text/javascript", "Content-Security-Policy" => "x" }, ["js"]] } }
  let(:app) { described_class.new(inner) }

  it "serves the worker script with a policy that loads nothing" do
    _, headers, = app.call("PATH_INFO" => "/vendor/vega/vega-worker.mjs")
    expect(headers["content-security-policy"]).to eq("default-src 'none'")
    expect(headers.keys.grep(/content-security-policy/i)).to eq(["content-security-policy"])
  end

  it "leaves other responses as they are" do
    _, headers, = app.call("PATH_INFO" => "/js/monadic.js")
    expect(headers).to eq("content-type" => "text/javascript", "Content-Security-Policy" => "x")
  end

  it "is in the server's stack" do
    expect(File.read(File.expand_path("../../../config.ru", __dir__))).to include("use Monadic::Workbench::WorkerPolicy")
  end
end
