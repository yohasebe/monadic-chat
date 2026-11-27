# frozen_string_literal: true

require "spec_helper"
require "json"
require_relative "../../../lib/monadic/shared_tools/mistral_search"
require_relative "../../../lib/monadic/shared_tools/parallel_dispatch"

module MonadicHelper
end unless defined?(MonadicHelper)

RSpec.describe Monadic::SharedTools::MistralSearch do
  let(:api_key) { "ms-spec-mistral-key" }

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

  def response(content, searched: true)
    outputs = []
    outputs << { "type" => "tool.execution", "name" => "web_search", "arguments" => "{}" } if searched
    outputs << { "type" => "message.output", "model" => "m", "role" => "assistant", "content" => content }
    { "object" => "conversation.response", "conversation_id" => "conv_1", "outputs" => outputs,
      "usage" => { "prompt_tokens" => 1, "connectors" => { "web_search" => 1 } }, "guardrails" => nil }
  end

  let(:chunks) do
    [
      { "type" => "text", "text" => "Ruby 4 was released." },
      { "type" => "tool_reference", "tool" => "web_search", "title" => "Ruby news", "url" => "https://example.com/ruby", "source" => nil },
      { "type" => "text", "text" => " It adds a new parser." },
      { "type" => "tool_reference", "tool" => "web_search", "title" => "Parser", "url" => "https://example.com/parser", "source" => nil },
      { "type" => "tool_reference", "tool" => "web_search", "title" => "Ruby news", "url" => "https://example.com/ruby", "source" => nil }
    ]
  end

  describe ".search" do
    it "posts a one-shot conversation with only the web_search tool, not stored, with the key in the Authorization header" do
      sent = stub_requests([200, response(chunks)])
      described_class.search(query: "latest Ruby release", api_key: api_key, model: "spec-model")

      expect(sent.size).to eq(1)
      url, headers, body = sent.first
      expect(url).to eq("https://api.mistral.ai/v1/conversations")
      expect(headers["Authorization"] == "Bearer #{api_key}").to be(true)
      expect(headers["Content-Type"]).to eq("application/json")
      expect(headers["Accept"]).to eq("application/json")
      expect(body).to eq("model" => "spec-model", "inputs" => "latest Ruby release",
                         "instructions" => described_class::INSTRUCTIONS,
                         "tools" => [{ "type" => "web_search" }], "store" => false)
      expect(body).not_to have_key("stream")
    end

    it "sends Mistral's default chat model when none is given" do
      allow(SystemDefaults).to receive(:get_default_model).with("mistral").and_return("default-model")
      sent = stub_requests([200, response(chunks)])
      described_class.search(query: "ruby", api_key: api_key)
      expect(sent.first[2]["model"]).to eq("default-model")
    end

    it "gives the model the answer, with each citation numbered by its source in order, and the sources once each" do
      stub_requests([200, response(chunks)])
      found = described_class.search(query: "ruby", api_key: api_key, model: "m")

      expect(found).to eq(
        "query" => "ruby",
        "answer" => "Ruby 4 was released. [1] It adds a new parser. [2] [1]",
        "sources" => [{ "title" => "Ruby news", "url" => "https://example.com/ruby" },
                      { "title" => "Parser", "url" => "https://example.com/parser" }],
        "websearch_agent" => "mistral"
      )
    end

    it "takes content given as a string" do
      stub_requests([200, response("Plain answer.")])
      found = described_class.search(query: "ruby", api_key: api_key, model: "m")
      expect(found.slice("answer", "sources")).to eq("answer" => "Plain answer.", "sources" => [])
    end

    it "says so when the web was not searched" do
      stub_requests([200, response("From memory.", searched: false)])
      found = described_class.search(query: "ruby", api_key: api_key, model: "m")
      expect(found["answer"]).to eq("From memory.")
      expect(found["note"]).to include("not searched")
    end

    it "gives an error for a reply with no answer and no sources" do
      stub_requests([200, { "outputs" => [] }])
      expect(described_class.search(query: "ruby", api_key: api_key, model: "m"))
        .to eq("error" => "Mistral web search error: the search gave no answer.")
    end

    it "sends nothing for an empty or too long query, or without a key" do
      sent = stub_requests([200, response(chunks)])
      expect(described_class.search(query: "  ", api_key: api_key)["error"]).to include("empty")
      expect(described_class.search(query: "x" * (described_class::MAX_QUERY_LENGTH + 1), api_key: api_key)["error"])
        .to include(described_class::MAX_QUERY_LENGTH.to_s)
      expect(described_class.search(query: "ruby", api_key: "")["error"]).to include("MISTRAL_API_KEY")
      expect(sent).to be_empty
    end

    {
      401 => { "message" => "Unauthorized" },
      402 => { "detail" => "Payment required" },
      429 => { "error" => { "message" => "Rate limit exceeded" } },
      500 => { "object" => "error", "message" => "Internal error", "type" => "internal", "code" => "500" }
    }.each do |status, body|
      it "gives the model the API's message for HTTP #{status}, once and without the key" do
        key_in = body.transform_values { |v| v.is_a?(String) && v != "error" ? "#{v} (key #{api_key})" : v }
        sent = stub_requests([status, key_in])
        found = described_class.search(query: "ruby", api_key: api_key, model: "m")

        expected = (body["message"] || body["detail"] || body.dig("error", "message"))
        expect(sent.size).to eq(1)
        expect(found.keys).to eq(["error"])
        expect(found["error"]).to start_with("Mistral web search error: #{expected}")
        expect(found["error"]).to include(status.to_s)
        expect(found["error"].include?(api_key)).to be(false)
      end
    end

    it "reads a list of details" do
      stub_requests([422, { "detail" => [{ "msg" => "field required" }, { "msg" => "bad tool" }] }])
      expect(described_class.search(query: "ruby", api_key: api_key, model: "m")["error"])
        .to eq("Mistral web search error: field required; bad tool (HTTP 422)")
    end

    it "gives an error for a body that is not JSON" do
      stub_requests([502, "Bad Gateway"])
      expect(described_class.search(query: "ruby", api_key: api_key, model: "m"))
        .to eq("error" => "Mistral web search error: HTTP 502")
    end

    it "gives an error for a successful status with a body that is not JSON" do
      stub_requests([200, "<html>"])
      expect(described_class.search(query: "ruby", api_key: api_key, model: "m"))
        .to eq("error" => "Mistral web search error: HTTP 200")
    end

    it "gives an error for a request that fails on the network, without the key" do
      chain = double("http")
      allow(HTTP).to receive(:timeout).and_return(chain)
      allow(chain).to receive(:headers).and_return(chain)
      allow(chain).to receive(:post).and_raise(HTTP::ConnectionError, "offline #{api_key}")
      expect(described_class.search(query: "ruby", api_key: api_key, model: "m"))
        .to eq("error" => "Mistral web search error: offline [REDACTED]")
    end
  end

  describe "parallel dispatch in a Mistral app" do
    let(:app) do
      Class.new do
        include MonadicSharedTools::ParallelDispatch

        def resolve_provider_config
          MonadicSharedTools::ParallelDispatch::PROVIDER_CONFIG["MistralHelper"]
        end
      end.new
    end

    let(:completion) { { "choices" => [{ "message" => { "content" => "Subtask answer" } }] } }

    # Each request as [url, body]: Mistral's search, then the subtask's
    # chat completion. search_status: the status of the search's reply.
    def stub_dispatch_requests(search_status: 200)
      sent = []
      chain = double("http")
      allow(HTTP).to receive(:timeout).and_return(chain)
      allow(HTTP).to receive(:headers).and_return(chain)
      allow(chain).to receive(:timeout).and_return(chain)
      allow(chain).to receive(:headers).and_return(chain)
      allow(chain).to receive(:post) do |url, json:|
        sent << [url.to_s, JSON.parse(JSON.generate(json))]
        status, reply = url.to_s.include?("/v1/conversations") ? [search_status, response(chunks)] : [200, completion]
        double("res", status: HTTP::Response::Status.new(status), body: double(to_s: JSON.generate(reply)))
      end
      sent
    end

    before do
      allow(app).to receive(:send_parallel_progress)
      stub_const("CONFIG", CONFIG.to_h.merge("MISTRAL_API_KEY" => api_key, "TAVILY_API_KEY" => "tavily-key"))
    end

    let(:session) { { parameters: { "model" => "mistral-spec-model", "websearch" => true } } }

    it "prefetches Mistral's search for a subtask asked to search, and sends nothing to Tavily" do
      sent = stub_dispatch_requests
      result = app.dispatch_parallel_tasks(tasks: [{ "id" => "t1", "prompt" => "Latest Ruby release" }],
                                           websearch: true, session: session)

      urls = sent.map(&:first)
      expect(urls).to contain_exactly("https://api.mistral.ai/v1/conversations",
                                      "https://api.mistral.ai/v1/chat/completions")
      expect(urls.grep(/tavily/)).to be_empty
      search_body = sent.find { |u, _| u.include?("/v1/conversations") }.last
      expect(search_body).to include("inputs" => "Latest Ruby release", "tools" => [{ "type" => "web_search" }],
                                     "store" => false)
      completion_body = sent.find { |u, _| u.include?("chat/completions") }.last
      expect(completion_body["model"]).to eq("mistral-spec-model")
      prompt = completion_body.dig("messages", 0, "content")
      expect(prompt).to include("=== Web Search Results ===", "Ruby 4 was released.", "https://example.com/parser",
                                "Latest Ruby release")
      expect(result).to include("Subtask answer")
    end

    it "searches for the start of a long subtask only" do
      sent = stub_dispatch_requests
      long = "word " * 200
      app.dispatch_parallel_tasks(tasks: [{ "id" => "t1", "prompt" => long }], websearch: true, session: session)
      query = sent.find { |u, _| u.include?("/v1/conversations") }.last["inputs"]
      expect(query.length).to be <= described_class::PREFETCH_QUERY_LENGTH
    end

    it "makes no search for a subtask not asked to search" do
      sent = stub_dispatch_requests
      app.dispatch_parallel_tasks(tasks: [{ "id" => "t1", "prompt" => "Latest Ruby release" }], session: session)
      expect(sent.map(&:first)).to eq(["https://api.mistral.ai/v1/chat/completions"])
    end

    it "makes no search when the message may not search" do
      sent = stub_dispatch_requests
      app.dispatch_parallel_tasks(tasks: [{ "id" => "t1", "prompt" => "Latest Ruby release" }], websearch: true,
                                  session: { parameters: { "model" => "mistral-spec-model", "websearch" => false } })
      expect(sent.map(&:first)).to eq(["https://api.mistral.ai/v1/chat/completions"])
    end

    it "sends the subtask with its prompt as it is when the search fails" do
      sent = stub_dispatch_requests(search_status: 429)
      app.dispatch_parallel_tasks(tasks: [{ "id" => "t1", "prompt" => "Latest Ruby release" }],
                                  websearch: true, session: session)
      prompt = sent.find { |u, _| u.include?("chat/completions") }.last.dig("messages", 0, "content")
      expect(prompt).to eq("Latest Ruby release")
    end
  end
end
