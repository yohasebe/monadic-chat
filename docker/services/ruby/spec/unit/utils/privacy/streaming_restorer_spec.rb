# frozen_string_literal: true

require 'monadic/utils/privacy/streaming_restorer'

RSpec.describe Monadic::Utils::Privacy::StreamingRestorer do
  # Stub pipeline that just substitutes from a fixed registry — exercises
  # the restorer's buffering logic without depending on the real backend.
  class FakePipeline
    def initialize(registry)
      @registry = registry
    end

    def after_receive_from_llm(text)
      restored = text.dup
      @registry.each { |ph, val| restored.gsub!(ph, val) }
      Struct.new(:text).new(restored)
    end
  end

  let(:registry) do
    { "<<PERSON_1>>" => "Alice", "<<EMAIL_ADDRESS_1>>" => "alice@x.com" }
  end
  subject(:restorer) { described_class.new(FakePipeline.new(registry)) }

  it "withholds short chunks until enough text accumulates" do
    out = restorer.feed("Hi ")
    expect(out).to eq("")
  end

  it "restores complete placeholders inside a long chunk" do
    chunk = "Hello <<PERSON_1>>, this is a long message #{'x' * 200}"
    out = restorer.feed(chunk)
    expect(out).to include("Alice")
    expect(out).not_to include("<<PERSON_1>>")
  end

  it "does not split a placeholder across feed boundaries" do
    long_prefix = 'x' * 80
    restorer.feed("#{long_prefix}<<PER")
    out2 = restorer.feed("SON_1>> hello")
    flushed = out2 + restorer.flush
    expect(flushed).to include("Alice")
    expect(flushed).not_to include("<<PERSON_1>>")
    expect(flushed).not_to include("<<PER")
  end

  it "flushes everything on terminal call" do
    restorer.feed("Hi <<PERSON_1>>")
    out = restorer.flush
    expect(out).to include("Alice")
  end

  it "leaves unknown placeholders intact" do
    chunk = "Greetings <<UNKNOWN_99>> from #{'x' * 100}"
    out = restorer.feed(chunk) + restorer.flush
    expect(out).to include("<<UNKNOWN_99>>")
  end
end
