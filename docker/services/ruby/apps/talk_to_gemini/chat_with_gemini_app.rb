# frozen_string_literal: true

require_relative "./gemini_helper"

class ChatWithGemini < MonadicApp
  include GeminiHelper

  def icon
    "<i class='fab fa-google'></i>"
  end

  def description
    "This app accesses the Google Gemini API to answer questions about a wide range of topics."
  end

  attr_reader :models

  def initialize
    @models = list_models
    super
  end

  def list_models
    return @models if @models && !@models.empty?

    api_key = CONFIG["GEMINI_API_KEY"]
    return [] if api_key.nil?

    headers = {
      "Content-Type" => "application/json"
    }

    target_uri = "#{API_ENDPOINT}/models?key=#{api_key}"
    http = HTTP.headers(headers)

    begin
      res = http.get(target_uri)

      if res.status.success?
        model_data = JSON.parse(res.body)
        models = []
        model_data["models"].each do |model|
          name = model["name"].split("/").last
          display_name = model["displayName"]
          models << name if name && /Legacy/ !~ display_name
        end
      end

      models.filter do |model|
        /(?:embedding|aqa|vision)/ !~ model && model != "gemini-pro"
      end.reverse
    rescue HTTP::Error, HTTP::TimeoutError
      []
    end
  end

  def initial_prompt
    text = <<~TEXT
      You are a friendly and professional consultant with real-time, up-to-date information about almost anything. You are able to answer various types of questions, write computer program code, make decent suggestions, and give helpful advice in response to a prompt from the user. If the prompt is unclear, ask the user to rephrase it.

      Use the same language as the user and insert an emoji that you deem appropriate for the user's input at the beginning of your response. Use Japanese, for example, if the user's input is in Japanese.

      Your response must be formatted as a valid Markdown document.
    TEXT
    text.strip
  end

  def settings
    {
      "disabled": !CONFIG["GEMINI_API_KEY"],
      "app_name": "▷ Google Gemini (Chat)",
      "context_size": 20,
      "initial_prompt": initial_prompt,
      "description": description,
      "icon": icon,
      "easy_submit": false,
      "auto_speech": false,
      "initiate_from_assistant": false,
      "image": true,
      "models": @models,
      "model": "gemini-1.5-flash"
    }
  end
end
