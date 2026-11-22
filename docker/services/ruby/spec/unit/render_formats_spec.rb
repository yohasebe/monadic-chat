# frozen_string_literal: true

require_relative "../spec_helper"
require "tmpdir"
require_relative "../../lib/monadic/render_formats"

RSpec.describe Monadic::RenderFormats do
  def table_file(entries)
    path = File.join(Dir.mktmpdir("render-formats-spec"), "formats.json")
    File.write(path, JSON.generate(entries))
    path
  end

  def entry(id, fences: [], extensions: [], compound: [])
    { "id" => id, "fences" => fences, "extensions" => extensions, "compound_extensions" => compound }
  end

  it "answers the cases the page's registry is tested with" do
    cases = JSON.parse(File.read(File.expand_path("../../../../../test/fixtures/render_format_cases.json", __dir__)))
    expect(cases.size).to be > 10
    cases.each { |c| expect([c["name"], described_class.for_name(c["name"])]).to eq([c["name"], c["id"]]) }
  end

  it "names a file's kind by its extension, two-part extensions first, in any case" do
    expect(described_class.for_name("Sales.VL.JSON")).to eq("vega_lite")
    expect(described_class.for_name("reports/notes.md")).to eq("markdown")
    expect(described_class.for_name("flow.MMD")).to eq("diagram")
    expect(described_class.for_name("data.json")).to be_nil
    expect(described_class.for_name(".vl.json")).to be_nil
    expect(described_class.for_name("no-extension")).to be_nil
  end

  it "gives the page the same table, safe inside a script element" do
    expect(JSON.parse(described_class::FORMATS_JSON)).to eq(described_class::TABLE)
    expect(described_class::FORMATS_JSON).not_to include("</")
  end

  it "refuses a table that names an id, a fence or an extension twice, or is not of its form" do
    [
      [entry("a", extensions: ["x"]), entry("a", extensions: ["y"])],
      [entry("a", fences: ["m"]), entry("b", fences: ["m"])],
      [entry("a", extensions: ["x"]), entry("b", compound: ["x"])],
      [entry("a", extensions: ["X"])],
      [entry("a").merge("more" => [])],
      [entry("a").except("fences")],
      { "a" => 1 }
    ].each do |bad|
      expect { described_class.load(table_file(bad)) }.to raise_error(ArgumentError), bad.inspect
    end
    expect(described_class.load(table_file([entry("a", fences: ["m"], extensions: ["x"])])).first["id"]).to eq("a")
  end
end
