# frozen_string_literal: true

require "spec_helper"
require "json"
require_relative "../../../lib/monadic/shared_tools/deepseek_search"
require_relative "../../../lib/monadic/shared_tools/parallel_dispatch"

module MonadicHelper
end unless defined?(MonadicHelper)

RSpec.describe Monadic::SharedTools::DeepSeekSearch do
  let(:api_key) { "sk-spec-deepseek-key" }

  # Every request made, as [url, headers, body]; each answered with the next
  # of the replies ([status, body]), the last given again.
  def stub_requests(*replies)
    sent = []
    chain = double("http")
    allow(HTTP).to receive(:timeout).and_return(chain)
    allow(HTTP).to receive(:headers).and_return(chain)
    allow(chain).to receive(:timeout).and_return(chain)
    allow(chain).to receive(:headers) do |headers|
      @headers = headers
      chain
    end
    allow(chain).to receive(:post) do |url, json:|
      sent << [url.to_s, @headers, JSON.parse(JSON.generate(json))]
      status, body = replies.length > 1 ? replies.shift : replies.first
      text = body.is_a?(String) ? body : JSON.generate(body)
      double("res", status: HTTP::Response::Status.new(status), body: double(to_s: text))
    end
    sent
  end

  let(:results) do
    [
      { "rerank_score" => 0.9, "title" => "Ruby", "url" => "https://example.com/ruby", "snippet" => "short",
        "summary" => "A summary for models.", "content" => "full", "site_name" => "Example", "site_icon" => "i",
        "date" => "2026-01-02T03:04:05Z", "authority" => 1 },
      { "title" => "No summary", "url" => "https://example.com/other", "snippet" => "Only a snippet.", "date" => nil }
    ]
  end

  describe ".search" do
    it "posts the query and count with the key in the Authorization header" do
      sent = stub_requests([200, { "results" => results }])
      described_class.search(query: "ruby release site:example.com", count: 7, api_key: api_key)

      expect(sent.size).to eq(1)
      url, headers, body = sent.first
      expect(url).to eq("https://api.deepseek.com/v1/tools/search")
      expect(headers["Authorization"] == "Bearer #{api_key}").to be(true)
      expect(headers["Content-Type"]).to eq("application/json")
      expect(body).to eq({ "query" => "ruby release site:example.com", "count" => 7 })
    end

    it "gives the model the title, url, summary (or snippet) and date of each result" do
      stub_requests([200, { "results" => results }])
      found = described_class.search(query: "ruby", api_key: api_key)

      expect(found).to eq(
        "query" => "ruby",
        "results" => [
          { "title" => "Ruby", "url" => "https://example.com/ruby", "summary" => "A summary for models.",
            "date" => "2026-01-02T03:04:05Z" },
          { "title" => "No summary", "url" => "https://example.com/other", "summary" => "Only a snippet." }
        ],
        "websearch_agent" => "deepseek"
      )
    end

    it "uses the default count, and keeps a count within what the API takes" do
      sent = stub_requests([200, { "results" => [] }])
      described_class.search(query: "a", api_key: api_key)
      described_class.search(query: "b", count: 500, api_key: api_key)
      described_class.search(query: "c", count: 0, api_key: api_key)
      expect(sent.map { |s| s[2]["count"] }).to eq([described_class::DEFAULT_COUNT, described_class::MAX_COUNT,
                                                    described_class::DEFAULT_COUNT])
    end

    it "gives an empty list for a search that finds nothing" do
      stub_requests([200, { "results" => [] }])
      expect(described_class.search(query: "nothing", api_key: api_key)["results"]).to eq([])
    end

    it "sends nothing for an empty or too long query, or without a key" do
      sent = stub_requests([200, { "results" => [] }])
      expect(described_class.search(query: "  ", api_key: api_key)["error"]).to include("empty")
      expect(described_class.search(query: "x" * 129, api_key: api_key)["error"]).to include("128")
      expect(described_class.search(query: "ruby", api_key: "")["error"]).to include("DEEPSEEK_API_KEY")
      expect(sent).to be_empty
    end

    {
      401 => "Authentication Fails",
      402 => "Insufficient Balance",
      429 => "Rate Limit Reached"
    }.each do |status, message|
      it "gives the model the API's message for HTTP #{status}, once and without the key" do
        sent = stub_requests([status, { "error" => { "message" => "#{message} (key #{api_key})", "type" => "t",
                                                     "param" => nil, "code" => status.to_s } }])
        found = described_class.search(query: "ruby", api_key: api_key)

        expect(sent.size).to eq(1)
        expect(found.keys).to eq(["error"])
        expect(found["error"]).to start_with("DeepSeek search error: #{message}")
        expect(found["error"]).to include(status.to_s)
        expect(found["error"].include?(api_key)).to be(false)
      end
    end

    it "gives an error for a body that is not JSON" do
      stub_requests([502, "Bad Gateway"])
      expect(described_class.search(query: "ruby", api_key: api_key)["error"]).to eq("DeepSeek search error: HTTP 502")
    end

    it "gives an error for a request that fails on the network" do
      chain = double("http")
      allow(HTTP).to receive(:timeout).and_return(chain)
      allow(chain).to receive(:headers).and_return(chain)
      allow(chain).to receive(:post).and_raise(HTTP::ConnectionError, "offline")
      expect(described_class.search(query: "ruby", api_key: api_key)).to eq("error" => "DeepSeek search error: offline")
    end
  end

  describe ".fetch" do
    it "posts the url and gives the page's title and markdown" do
      sent = stub_requests([200, { "title" => "Page", "content" => "# Heading\n\nText" }])
      page = described_class.fetch(url: "https://example.com/page", api_key: api_key)

      url, headers, body = sent.first
      expect(url).to eq("https://api.deepseek.com/v1/tools/fetch")
      expect(headers["Authorization"] == "Bearer #{api_key}").to be(true)
      expect(body).to eq({ "url" => "https://example.com/page" })
      expect(page).to eq("title" => "Page", "url" => "https://example.com/page", "content" => "# Heading\n\nText",
                         "websearch_agent" => "deepseek")
    end

    it "gives an error for HTTP 404 (no content could be got)" do
      stub_requests([404, { "error" => { "message" => "Content not found", "code" => "404" } }])
      expect(described_class.fetch(url: "https://example.com/gone", api_key: api_key)["error"])
        .to start_with("DeepSeek fetch error: Content not found")
    end

    it "sends nothing for a url the API does not take" do
      sent = stub_requests([200, { "title" => "", "content" => "" }])
      ["", "ftp://example.com/f", "https://user:pass@example.com/", "https://example.com/#{"a" * 8200}"].each do |url|
        expect(described_class.fetch(url: url, api_key: api_key)).to have_key("error")
      end
      expect(sent).to be_empty
    end
  end

  describe "parallel dispatch in a DeepSeek app" do
    let(:app) do
      Class.new do
        include MonadicSharedTools::ParallelDispatch

        def resolve_provider_config
          MonadicSharedTools::ParallelDispatch::PROVIDER_CONFIG["DeepSeekHelper"]
        end
      end.new
    end

    let(:completion) { { "choices" => [{ "message" => { "content" => "Subtask answer" } }] } }

    # Each request as [url, body]: DeepSeek's search, then the subtask's
    # chat completion.
    def stub_dispatch_requests
      sent = []
      chain = double("http")
      allow(HTTP).to receive(:timeout).and_return(chain)
      allow(HTTP).to receive(:headers).and_return(chain)
      allow(chain).to receive(:timeout).and_return(chain)
      allow(chain).to receive(:headers).and_return(chain)
      allow(chain).to receive(:post) do |url, json:|
        sent << [url.to_s, JSON.parse(JSON.generate(json))]
        reply = url.to_s.include?("/v1/tools/search") ? { "results" => results } : completion
        double("res", status: HTTP::Response::Status.new(200), body: double(to_s: JSON.generate(reply)))
      end
      sent
    end

    before do
      allow(app).to receive(:send_parallel_progress)
      stub_const("CONFIG", CONFIG.to_h.merge("DEEPSEEK_API_KEY" => api_key, "TAVILY_API_KEY" => "tavily-key"))
    end

    let(:session) { { parameters: { "model" => "deepseek-v4-flash", "websearch" => true } } }

    it "prefetches DeepSeek search results for a subtask asked to search, and sends nothing to Tavily" do
      sent = stub_dispatch_requests
      result = app.dispatch_parallel_tasks(tasks: [{ "id" => "t1", "prompt" => "Latest Ruby release" }],
                                           websearch: true, session: session)

      urls = sent.map(&:first)
      expect(urls).to contain_exactly("https://api.deepseek.com/v1/tools/search",
                                      "https://api.deepseek.com/chat/completions")
      expect(urls.grep(/tavily/)).to be_empty
      search_body = sent.find { |u, _| u.include?("/v1/tools/search") }.last
      expect(search_body).to eq({ "query" => "Latest Ruby release", "count" => 3 })
      prompt = sent.find { |u, _| u.include?("chat/completions") }.last.dig("messages", 0, "content")
      expect(prompt).to include("=== Web Search Results ===", "A summary for models.", "Latest Ruby release")
      expect(result).to include("Subtask answer")
    end

    it "makes no search for a subtask not asked to search" do
      sent = stub_dispatch_requests
      app.dispatch_parallel_tasks(tasks: [{ "id" => "t1", "prompt" => "Latest Ruby release" }], session: session)
      expect(sent.map(&:first)).to eq(["https://api.deepseek.com/chat/completions"])
    end

    it "sends the subtask with its prompt as it is when the search fails" do
      sent = []
      chain = double("http")
      allow(HTTP).to receive(:timeout).and_return(chain)
      allow(HTTP).to receive(:headers).and_return(chain)
      allow(chain).to receive(:timeout).and_return(chain)
      allow(chain).to receive(:headers).and_return(chain)
      allow(chain).to receive(:post) do |url, json:|
        sent << [url.to_s, JSON.parse(JSON.generate(json))]
        status, reply = url.to_s.include?("/v1/tools/search") ? [402, { "error" => { "message" => "Insufficient Balance" } }] : [200, completion]
        double("res", status: HTTP::Response::Status.new(status), body: double(to_s: JSON.generate(reply)))
      end
      app.dispatch_parallel_tasks(tasks: [{ "id" => "t1", "prompt" => "Latest Ruby release" }],
                                  websearch: true, session: session)
      prompt = sent.find { |u, _| u.include?("chat/completions") }.last.dig("messages", 0, "content")
      expect(prompt).to eq("Latest Ruby release")
    end
  end
end
