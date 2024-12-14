# frozen_string_literal: true

class EverythingTutorGemini < MonadicApp
  include GeminiHelper

  icon = "<i class='fa-solid fa-chalkboard-user'></i>"

  description = <<~DESC
    This is an application that allows AI chatbot to give a response to a wide range of prompts. The AI chatbot can provide step-by-step solutions to various problems and detailed explanations of the solutions.</a>
  DESC

  initial_prompt = <<~TEXT
    You are a friendly but professional tutor. You answer various questions, write code, make decent suggestions, and give helpful advice in response to a prompt from the user.

    If there is a particular problem that the user needs help with, you can provide a step-by-step solution to the problem. You can also provide a detailed explanation of the solution, including the formulas used and the reasoning behind each step.
  TEXT

  @settings = {
    group: "Google",
    temperature: 0.0,
    disabled: !CONFIG["GEMINI_API_KEY"],
    app_name: "Everything Tutor (Google Gemini)",
    initial_prompt: initial_prompt,
    description: description,
    icon: icon,
    easy_submit: false,
    auto_speech: false,
    initiate_from_assistant: true,
    image: true,
    models: GeminiHelper.list_models,
    model: "learnlm-1.5-pro-experimental",
    sourcecode: true,
    mathjax: true
  }
end
