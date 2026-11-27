# frozen_string_literal: true

require 'json'
require_relative '../utils/http_client'
require_relative '../utils/error_formatter'
require_relative '../utils/extra_logger'
require_relative '../utils/system_defaults'

module Monadic
  module SharedTools
    # Web search for Mistral chats through Mistral's own web search, with the
    # chat's Mistral key.
    #
    # Mistral's web search runs on the Conversations API, not on the chat
    # completions the Mistral helper sends. The chat model is offered one
    # function tool (mistral_web_search); a call of it sends a one-shot
    # Conversations request whose only tool is web_search (not stored, not
    # streamed), with Mistral's default chat model (SystemDefaults: the
    # MISTRAL_DEFAULT_MODEL setting, then providerDefaults), and gives the
    # chat model the answer and its sources.
    #
    # Source of truth for:
    #   - The function schema that the Mistral helper offers when the
    #     message may search the web.
    #   - The system-prompt fragment that tells the model when to use it.
    #   - The request and the result given to the model, for the chat's tool
    #     and for the subtasks of parallel dispatch.
    #
    # Each request is billed, so one is made only when the tool is called (or
    # a subtask asked to search runs); none is retried.
    module MistralSearch
      ENDPOINT = "https://api.mistral.ai/v1/conversations"

      MAX_QUERY_LENGTH = 2000
      # The length of the start of a subtask's prompt that parallel dispatch
      # searches for.
      PREFETCH_QUERY_LENGTH = 400

      # A search and the answer written from it are one request.
      TIMEOUTS = { connect: 10, read: 120, write: 30 }.freeze

      FALLBACK_MODEL = "mistral-medium-latest"

      INSTRUCTIONS = "Search the web and report what you find, with sources."

      TOOL_NAMES = %w[mistral_web_search].freeze

      TOOLS = [
        {
          type: "function",
          function: {
            name: "mistral_web_search",
            description: "search the web for the given query and return an answer written from the pages found, with the title and url of each source.",
            parameters: {
              type: "object",
              properties: {
                query: {
                  type: "string",
                  description: "what to search the web for: a question or keywords."
                }
              },
              required: ["query"]
            }
          }
        }
      ].freeze

      PROMPT = <<~TEXT

        Web search is available through mistral_web_search. Use it when the user asks you to, or when the answer needs current information or a fact you should check; not for what you can answer as it is, or when the user asks you not to. Always respond to the user in the language they used. When you use what you found, cite the sources as HTML links: <a href="URL" target="_blank" rel="noopener noreferrer">Title</a>.
      TEXT

      module_function

      # The result of a search, for the model: { "query", "answer",
      # "sources" => [{ "title", "url" }], "websearch_agent" } (with a
      # "note" when the web was not searched), or { "error" => ... }. In the
      # answer, each citation is the number of its source ([1], [2], ...).
      def search(query:, api_key:, model: nil)
        query = query.to_s.strip
        return { "error" => "Mistral web search error: the query is empty." } if query.empty?
        if query.length > MAX_QUERY_LENGTH
          return { "error" => "Mistral web search error: the query must be #{MAX_QUERY_LENGTH} characters or fewer." }
        end

        api_key = api_key.to_s.strip
        return { "error" => "Mistral web search error: MISTRAL_API_KEY is not set." } if api_key.empty?

        parsed = post(request_body(query, model), api_key)
        return parsed if parsed.key?("error")

        result(query, parsed)
      end

      def request_body(query, model)
        model = model.to_s.strip
        model = SystemDefaults.get_default_model("mistral").to_s.strip if model.empty?
        model = FALLBACK_MODEL if model.empty?
        { "model" => model, "inputs" => query, "instructions" => INSTRUCTIONS,
          "tools" => [{ "type" => "web_search" }], "store" => false }
      end

      def result(query, parsed)
        outputs = Array(parsed["outputs"]).select { |o| o.is_a?(Hash) }
        searched = outputs.any? { |o| o["type"] == "tool.execution" }
        sources = []
        answer = outputs.select { |o| o["type"] == "message.output" }.map do |output|
          message_text(output["content"], sources)
        end.join("\n\n").strip
        return { "error" => "Mistral web search error: the search gave no answer." } if answer.empty? && sources.empty?

        found = { "query" => query, "answer" => answer, "sources" => sources, "websearch_agent" => "mistral" }
        found["note"] = "The web was not searched for this query." unless searched
        found
      end

      # The text of a message's content (a string, or text and tool_reference
      # chunks), each reference written as the number of its source, which is
      # added to sources once.
      def message_text(content, sources)
        return content.to_s unless content.is_a?(Array)

        content.map do |chunk|
          next chunk.to_s unless chunk.is_a?(Hash)

          case chunk["type"]
          when "text"
            chunk["text"].to_s
          when "tool_reference"
            url = chunk["url"].to_s
            next "" if url.empty?

            index = sources.index { |s| s["url"] == url }
            unless index
              sources << { "title" => chunk["title"].to_s.empty? ? url : chunk["title"].to_s, "url" => url }
              index = sources.length - 1
            end
            " [#{index + 1}]"
          else
            ""
          end
        end.join
      end

      # The parsed body of a successful request, or { "error" => ... } with
      # the API's message (the key taken out of it).
      def post(body, api_key)
        headers = { "Content-Type" => "application/json", "Accept" => "application/json",
                    "Authorization" => "Bearer #{api_key}" }
        res = Monadic::Utils::HttpClient.rest(**TIMEOUTS).headers(headers).post(ENDPOINT, json: body)
        text = res.body.to_s
        parsed = (JSON.parse(text) rescue nil)
        unless res.status.success? && parsed.is_a?(Hash)
          Monadic::Utils::ExtraLogger.log { "[Mistral] web search API error: HTTP #{res.status.to_i}" }
          return { "error" => "Mistral web search error: #{error_text(parsed, res.status.to_i, api_key)}" }
        end

        parsed
      rescue HTTP::Error => e
        { "error" => "Mistral web search error: #{clean(e.message, api_key)}" }
      end

      # The API's message in an error body ("message", "detail" or "error",
      # each a string, a hash with a message, or a list of them).
      def error_text(parsed, status, api_key)
        message = parsed.is_a?(Hash) ? %w[message detail error].lazy.map { |k| message_of(parsed[k]) }.find { |m| !m.empty? } : nil
        message = "HTTP #{status}" if message.to_s.strip.empty?
        message = "#{message} (HTTP #{status})" unless message.include?(status.to_s)
        clean(message, api_key)
      end

      def message_of(value)
        case value
        when Hash then message_of(value["message"] || value["msg"] || value["detail"])
        when Array then value.map { |v| message_of(v) }.reject(&:empty?).join("; ")
        else value.to_s.strip
        end
      end

      def clean(text, api_key)
        text = text.to_s
        text = text.gsub(api_key, "[REDACTED]") unless api_key.to_s.empty?
        Monadic::Utils::ErrorFormatter.scrub_identifiers(text)
      end
    end
  end
end
