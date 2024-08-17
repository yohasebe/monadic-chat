# frozen_string_literal: true

require_relative "./command_r_helper"

class ChatWithCommandR < MonadicApp
  include CommandRHelper

  def icon
    "<i class='fa-solid fa-c'></i>"
  end

  def description
    "This app accesses the Cohere Command R API to answer questions about a wide range of topics."
  end

  attr_reader :models

  def initialize
    @models = list_models
    super
  end

  def list_models
    return @models if @models && !@models.empty?

    api_key = CONFIG["COHERE_API_KEY"]
    return [] if api_key.nil?

    headers = {
      "Content-Type" => "application/json",
      "Authorization" => "Bearer #{api_key}"
    }

    target_uri = "#{API_ENDPOINT}/models"
    http = HTTP.headers(headers)

    begin
      res = http.get(target_uri)

      if res.status.success?
        model_data = JSON.parse(res.body)
        model_data["models"].map do |model|
          model["name"]
        end.filter do |model|
          !model.include?("embed") && !model.include?("rerank")
        end
      end
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
      "disabled": !CONFIG["COHERE_API_KEY"],
      "app_name": "▹ Cohere Command R (Chat)",
      "context_size": 20,
      "initial_prompt": initial_prompt,
      "description": description,
      "icon": icon,
      "easy_submit": false,
      "auto_speech": false,
      "initiate_from_assistant": false,
      "image": false,
      "models": @models,
      "model": "command-r"
    }
  end
end
