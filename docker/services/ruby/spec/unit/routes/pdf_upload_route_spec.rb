# frozen_string_literal: true

require "spec_helper"
require "rack/test"
require "sinatra/base"
require "tempfile"
require_relative "../../../lib/monadic/utils/pdf_text_extractor"
require_relative "../../../lib/monadic/utils/error_formatter"

# POST /pdf, run from the route file itself in an app of its own.
RSpec.describe "POST /pdf" do
  include Rack::Test::Methods

  let(:store) { double("PdfStore", store_embeddings: true) }
  let(:route_app) do
    route_file = File.expand_path("../../../lib/monadic/routes/pdf_routes.rb", __dir__)
    test_store = store
    Class.new(Sinatra::Base) do
      set :host_authorization, { permitted_hosts: [] }
      helpers do
        define_method(:pdf_store_for) { |_| test_store }
        def error_json(message) = { success: false, error: message }.to_json
      end
      class_eval(File.read(route_file), route_file)
    end
  end

  def app = route_app

  let(:upload) do
    file = Tempfile.new(["upload", ".pdf"])
    file.write("%PDF-1.4 test")
    file.rewind
    Rack::Test::UploadedFile.new(file.path, "application/pdf")
  end

  # The Tempfiles the route makes for the upload, to check they are gone.
  def track_route_tempfiles
    made = []
    allow(Tempfile).to receive(:new).and_wrap_original do |orig, *args, **kw|
      orig.call(*args, **kw).tap { |t| made << t if args.first == "temp_pdf" }
    end
    made
  end

  it "stores the chunks, splitting the text once" do
    pdf = double("PDF2Text", extract: nil)
    expect(pdf).to receive(:split_text).once.and_return([{ "text" => "chunk", "tokens" => 3 }])
    allow(PDF2Text).to receive(:new).and_return(pdf)
    made = track_route_tempfiles

    post "/pdf", { "pdfFile" => upload, "pdfTitle" => "T" }
    expect(JSON.parse(last_response.body)["success"]).to be true
    expect(store).to have_received(:store_embeddings).with(hash_including(title: "T", items: 1), [hash_including(text: "chunk")])
    expect(made.size).to eq(1)
    expect(made.first.path).to be_nil
  end

  it "removes its temporary copy when the extraction fails, and scrubs the error" do
    pdf = double("PDF2Text")
    allow(pdf).to receive(:extract).and_raise(RuntimeError, "boom")
    allow(PDF2Text).to receive(:new).and_return(pdf)
    made = track_route_tempfiles

    post "/pdf", { "pdfFile" => upload }
    body = JSON.parse(last_response.body)
    expect(body["success"]).to be false
    expect(body["error"]).to include("boom")
    expect(made.size).to eq(1)
    expect(made.first.path).to be_nil
  end
end
