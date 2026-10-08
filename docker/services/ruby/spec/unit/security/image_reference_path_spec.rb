# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require_relative "../../../lib/monadic/adapters/vendors/openai_helper"

# An image's `data` comes from the client. A file path in it may only name a
# file inside the shared folder; anything else would let a client have the
# server copy any readable file and send it to the provider.
RSpec.describe "OpenAI image generation references" do
  let(:helper) { Class.new { include OpenAIHelper }.new }

  around do |example|
    Dir.mktmpdir do |outside|
      Dir.mktmpdir do |shared|
        @outside = outside
        @shared = shared
        example.run
      end
    end
  end

  def refs_for(data)
    context = [{ "role" => "user", "images" => [{ "title" => "pic.png", "data" => data }] }]
    helper.send(:prepare_openai_image_generation_refs, context, true, "user", @shared)
  end

  it "does not copy a file outside the shared folder" do
    secret = File.join(@outside, "env")
    File.write(secret, "KEY=value")
    expect(refs_for(secret)).to be_empty
    expect(Dir.children(@shared)).to be_empty
  end

  it "does not follow a link inside the shared folder to a file outside it" do
    secret = File.join(@outside, "env")
    File.write(secret, "KEY=value")
    link = File.join(@shared, "innocent.png")
    File.symlink(secret, link)
    expect(refs_for(link)).to be_empty
    expect(Dir.children(@shared)).to eq(["innocent.png"])
  end

  it "copies a file that is inside the shared folder" do
    inside = File.join(@shared, "photo.png")
    File.binwrite(inside, "PNGDATA")
    expect(refs_for(inside).size).to eq(1)
  end

  it "still accepts a data URI" do
    expect(refs_for("data:image/png;base64,UE5HREFUQQ==").size).to eq(1)
  end
end
