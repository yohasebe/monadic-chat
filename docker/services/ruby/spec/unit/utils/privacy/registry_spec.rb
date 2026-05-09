# frozen_string_literal: true

require 'monadic/utils/privacy/registry'

RSpec.describe Monadic::Utils::Privacy::Registry do
  let(:session) { {} }
  subject(:reg) { described_class.new(session) }

  it "lazily initializes session state" do
    expect(reg.registry).to eq({})
    expect(reg.audit).to eq([])
    expect(reg.count).to eq(0)
  end

  it "persists state across multiple instances backed by the same session" do
    reg.merge!("<<PERSON_1>>" => "Alice")
    new_view = described_class.new(session)
    expect(new_view.registry).to eq("<<PERSON_1>>" => "Alice")
  end

  it "appends audit entries with timestamps" do
    reg.append_audit(:anonymize, added: ["<<PERSON_1>>"])
    expect(reg.audit.length).to eq(1)
    entry = reg.audit.first
    expect(entry[:op]).to eq(:anonymize)
    expect(entry[:added]).to eq(["<<PERSON_1>>"])
    expect(entry[:ts]).to be_a(Integer)
  end

  it "resets state on demand" do
    reg.merge!("<<X_1>>" => "y")
    reg.append_audit(:anonymize, added: ["<<X_1>>"])
    reg.reset!
    expect(reg.registry).to eq({})
    expect(reg.audit).to eq([])
  end

  describe ".strip_for_persist (RD-1: registry never touches disk)" do
    it "removes :privacy from monadic_state" do
      payload = {
        messages: [{ role: "user", text: "hi" }],
        monadic_state: {
          context: { foo: "bar" },
          privacy: { registry: { "<<PERSON_1>>" => "Alice" } }
        }
      }
      stripped = described_class.strip_for_persist(payload)
      expect(stripped[:monadic_state]).not_to have_key(:privacy)
      expect(stripped[:monadic_state][:context]).to eq(foo: "bar")
      # Must not mutate the input
      expect(payload[:monadic_state]).to have_key(:privacy)
    end

    it "is a no-op for payloads without monadic_state" do
      payload = { messages: [] }
      expect(described_class.strip_for_persist(payload)).to eq(payload)
    end
  end
end
