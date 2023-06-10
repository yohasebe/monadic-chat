# frozen_string_literal: true

require "dotenv/load"
require "pg"
require "spec_helper"
require_relative "../lib/embeddings/text_embeddings"

API_KEY = ENV["OPENAI_API_KEY"]

RSpec.describe "get_embeddings" do
  before(:all) do
    @text_db = TextEmbeddings.new("test_db", recreate_db: true)
  end

  after(:all) do
    @text_db.close_connection
  end

  describe "connect_to_db" do
    context "when given a valid database name" do
      it "connects to the database and sets up the table and extension" do
        expect(@text_db.conn).to be_a(PG::Connection)
        expect(@text_db.conn.status).to eq(PG::CONNECTION_OK)
        expect(@text_db.conn.exec("SELECT COUNT(*) FROM pg_catalog.pg_tables WHERE tablename = 'items'").first["count"]).to eq(1)
        expect(@text_db.conn.exec("SELECT COUNT(*) FROM pg_catalog.pg_extension WHERE extname = 'vector'").first["count"]).to eq(1)
      end
    end

    context "when given an invalid database name" do
      it "raises an error" do
        expect { TextEmbeddings.connect_to_db("invalid_db") }.to raise_error(PG::ConnectionBad)
      end
    end
  end

  describe "get_embeddings" do
    context "when given valid input text" do
      it "returns a non-empty text embedding" do
        text = "This is a test sentence."
        expect(API_KEY).not_to be_nil
        embedding = @text_db.get_embeddings(text, api_key: API_KEY)
        expect(embedding).to be_a(Array)
        expect(embedding).not_to be_empty
      end
    end

    context "when given empty input text" do
      it "raises an error" do
        expect { @text_db.get_embeddings("") }.to raise_error(StandardError)
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
        text1 = "This is a test sentence."
        metadata1 = { "author" => "John Doe", "date" => "2022-01-01" }
        @text_db.store_embeddings(text1, metadata1)

        text2 = "This is another test sentence."
        metadata2 = { "author" => "Jane Doe", "date" => "2022-01-02" }
        @text_db.store_embeddings(text2, metadata2)

        query_text = "This is a sentence."
        expect(@text_db.find_closest_text(query_text)["text"]).to eq(text1)
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
