require "spec_helper"
require_relative "../../lib/monadic/utils/document_store_registry"

RSpec.describe Monadic::Utils::DocumentStoreRegistry do
  let(:registry) { described_class }

  it "sanitizes app keys" do
    expect(registry.sanitize_app_key("ChatPlus OpenAI")).to eq("chatplus_openai")
  end

  it "sets and retrieves vector store id safely" do
    app = "spec_app"
    vs = "vs_test_123"
    registry.set_cloud_vs(app, vs)
    expect(registry.get_app(app).dig('cloud', 'vector_store_id')).to eq(vs)
  end

  it "adds cloud files without duplication" do
    app = "spec_app_dupe"
    fid = "file_abc"
    registry.set_cloud_vs(app, "vs_1")
    registry.add_cloud_file(app, file_id: fid, filename: "a.pdf", hash: "h1")
    registry.add_cloud_file(app, file_id: fid, filename: "a.pdf", hash: "h1")
    files = registry.get_app(app).dig('cloud', 'files')
    expect(files.count { |f| f['file_id'] == fid }).to eq(1)
  end
end

