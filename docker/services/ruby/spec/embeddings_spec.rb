# frozen_string_literal: true

require "dotenv/load"
require "pg"
require_relative "./spec_helper"
require_relative "../lib/monadic/utils/text_embeddings"

API_KEY = ENV["OPENAI_API_KEY"]
IN_CONTAINER = false

RSpec.describe "get_embeddings" do
  before(:all) do
    @text_db = TextEmbeddings.new("test_db", recreate_db: true)
  end

  after(:all) do
    @text_db.close_connection
  end

  describe "get_embeddings" do
    context "when given valid input text" do
      it "returns a non-empty text embedding" do
        text = "This is a test sentence."
        
        # Mock the HTTP response
        mock_response = double('response')
        allow(mock_response).to receive(:is_a?).with(Net::HTTPSuccess).and_return(true)
        allow(mock_response).to receive(:body).and_return(
          { data: [{ embedding: Array.new(1536) { rand } }] }.to_json
        )
        
        # Mock the HTTP request
        allow(Net::HTTP).to receive(:start).and_return(mock_response)
        
        embedding = @text_db.get_embeddings(text)
        expect(embedding).to be_a(Array)
        expect(embedding).not_to be_empty
      end
    end

    context "when given empty input text" do
      it "raises an error" do
        expect { @text_db.get_embeddings("") }.to raise_error(ArgumentError)
      end
    end

    context "when given invalid input text" do
      it "raises an error" do
        expect { @text_db.get_embeddings(nil) }.to raise_error(NoMethodError)
      end
    end
  end

  describe "find_closest_text" do
    context "when given valid input text" do
      it "returns the closest text in the database" do
        doc_title = "Test Document"
        doc_data = { title: doc_title, metadata: {} }

        text1 = "This is a test sentence."
        metadata1 = {
          "author" => "John Doe",
          "date" => "2022-01-01",
          "tokens" => 5
        }
        item_data1 = { text: text1, metadata: metadata1 }

        text2 = "This is yet another test sentence."
        metadata2 = { author: "Jane Doe", date: "2023-12-31", tokens: 6 }
        item_data2 = { text: text2, metadata: metadata2 }

        items_data = [item_data1, item_data2]

        res = @text_db.store_embeddings(doc_data, items_data)
        doc_id = res[:doc_id]

        # order starts from 1
        model = {
          doc_id: doc_id,
          doc_title: doc_title,
          text: text1,
          position: 1,
          total_items: 2,
          metadata: metadata1
        }
        query_text = "This is a test sentence."
        res = @text_db.find_closest_text(query_text, top_n: 1)
        expect(res.first).to eq(model)
      end
    end

    context "when given empty input text" do
      it "returns false" do
        text = ""
        expect(@text_db.find_closest_text(text)).to be_falsey
      end
    end
  end
end
