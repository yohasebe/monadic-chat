# frozen_string_literal: true

require_relative "../../spec_helper"
require "json"
require_relative "../../../lib/monadic/workbench/whiteboard_layout"

# Where the AI's shapes go on a whiteboard: boxes grow to their texts, new
# shapes move off what they partly cover, diagrams are laid out by their
# arrows, and what is still wrong is found.
RSpec.describe Monadic::Workbench::WhiteboardLayout do
  let(:layout) { described_class }

  def box(id, x, y, w = 160, h = 60, extra = {})
    { "id" => id, "type" => "rect", "x" => x.to_f, "y" => y.to_f, "w" => w.to_f, "h" => h.to_f }.merge(extra)
  end

  it "takes a wide character as wide as the text is tall, and others about 0.6 of it" do
    expect(layout.text_size("ab", 20)).to eq([24.0, 25.0])
    expect(layout.text_size("在庫", 20)).to eq([40.0, 25.0])
    expect(layout.text_size("a\nbcd", 20)).to eq([36.0, 50.0])
  end

  it "grows a box about its middle to hold its text, and not one that holds it" do
    small = box("a", 400, 400, 60, 40, "text" => "Inventory check", "size" => 20)
    expect(layout.fit!(small)).to be true
    expect(small["w"]).to eq((15 * 12) + 48.0)
    expect(small["x"]).to eq(400 - ((small["w"] - 60) / 2.0))
    expect(small["h"]).to eq(57.0)
    roomy = box("b", 0, 0, 400, 100, "text" => "OK", "size" => 20)
    expect(layout.fit!(roomy)).to be false
  end

  it "takes partly covering as an overlap, but not one box inside another" do
    expect(layout.overlap?([0, 0, 100, 100], [50, 50, 100, 100])).to be true
    expect(layout.overlap?([0, 0, 100, 100], [10, 10, 30, 30])).to be false
    expect(layout.overlap?([0, 0, 100, 100], [101, 0, 50, 50])).to be false
  end

  it "moves a shape that partly covers another to the nearest free place" do
    there = box("u", 400, 400)
    new_box = box("n", 450, 420)
    moved = layout.nudge!(new_box, [there])
    expect(moved).not_to be_nil
    expect(layout.overlap?(layout.bounds(new_box), layout.bounds(there))).to be false
    # The nearest: no farther than the overlap needs.
    expect(Math.hypot(*moved)).to be <= 120
    expect(layout.nudge!(box("m", 0, 0), [there])).to be_nil
  end

  it "stops looking for a free place when its time is up, and looks only near the shape" do
    there = box("u", 400, 400)
    new_box = box("n", 450, 420)
    expect(layout.nudge!(new_box, [there], deadline: Process.clock_gettime(Process::CLOCK_MONOTONIC) - 1)).to eq(:late)
    expect(new_box["x"]).to eq(450.0)
    # A crowd far away does not change where it goes.
    far = Array.new(500) { |i| box("f#{i}", 1500, (i % 25) * 40, 20, 20) }
    alone = box("m", 450, 420)
    expect(layout.nudge!(alone, [there] + far)).to eq(layout.nudge!(box("k", 450, 420), [there]))
  end

  it "finds the boxes an arrow goes through, but those it joins" do
    a = box("a", 100, 100)
    b = box("b", 400, 100)
    c = box("c", 700, 100)
    arrow = { "id" => "l", "type" => "arrow", "from" => "a", "to" => "c", "x1" => 180.0, "y1" => 130.0, "x2" => 780.0, "y2" => 130.0 }
    expect(layout.crossings(arrow, [a, b, c])).to eq(["b"])
    beside = { "id" => "m", "type" => "arrow", "x1" => 0.0, "y1" => 300.0, "x2" => 900.0, "y2" => 300.0 }
    expect(layout.crossings(beside, [a, b, c])).to eq([])
  end

  describe "the routes and text sizes the page computes too" do
    let(:cases) { JSON.parse(File.read(File.expand_path("../../../../../../test/fixtures/whiteboard_route_cases.json", __dir__))) }

    it "routes as the shared cases say" do
      cases["routes"].each do |c|
        expect(layout.route(c["a"], c["b"], c["obstacles"])).to eq(c["route"].map { |p| p.map(&:to_f) }), c["name"]
      end
    end

    it "sizes texts as the shared cases say" do
      cases["texts"].each { |c| expect(layout.text_size(c["text"], c["size"])).to eq(c["box"].map(&:to_f)) }
    end
  end

  it "lays out boxes in columns by their arrows, apart, below what is on the board" do
    boxes = [{ "id" => "a", "type" => "rect", "text" => "Start" }, { "id" => "b", "type" => "rect", "text" => "Left" },
             { "id" => "c", "type" => "rect", "text" => "Right" }, { "id" => "d", "type" => "ellipse", "text" => "End" }]
    issue = layout.layout!(boxes, [%w[a b], %w[a c], %w[b d], %w[c d]], "right", [[40, 40, 300, 200]])
    expect(issue).to be_nil
    at = boxes.to_h { |b| [b["id"], b] }
    expect(at["a"]["x"]).to be < at["b"]["x"]
    # A column's boxes share its middle.
    expect(at["b"]["x"] + (at["b"]["w"] / 2)).to eq(at["c"]["x"] + (at["c"]["w"] / 2))
    expect(at["d"]["x"]).to be > at["b"]["x"]
    expect(at["b"]["y"]).to be < at["c"]["y"]
    boxes.combination(2).each { |p, q| expect(layout.overlap?(layout.bounds(p), layout.bounds(q))).to be false }
    expect(boxes.map { |b| b["y"] }.min).to be >= 240 + layout::GAP
  end

  it "lays out in rows when asked, and says when the whole is larger than the board" do
    boxes = [{ "id" => "a", "type" => "rect", "text" => "A" }, { "id" => "b", "type" => "rect", "text" => "B" }]
    layout.layout!(boxes, [%w[a b]], "down", [])
    expect(boxes[0]["y"]).to be < boxes[1]["y"]
    expect(boxes[0]["x"] + (boxes[0]["w"] / 2)).to eq(boxes[1]["x"] + (boxes[1]["w"] / 2))
    many = Array.new(30) { |i| { "id" => "n#{i}", "type" => "rect", "text" => "Step #{i}" } }
    edges = (0...29).map { |i| ["n#{i}", "n#{i + 1}"] }
    expect(layout.layout!(many, edges, "right", [])).to match(/larger than the board/)
  end

  it "keeps the ranks finite when the arrows go round" do
    boxes = [{ "id" => "a", "type" => "rect" }, { "id" => "b", "type" => "rect" }]
    expect { layout.layout!(boxes, [%w[a b], %w[b a]], "right", []) }.not_to raise_error
    expect(boxes.map { |b| b["x"] }.uniq.size).to eq(2)
  end
end
