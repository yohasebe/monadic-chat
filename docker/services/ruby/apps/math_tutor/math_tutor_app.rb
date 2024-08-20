# We can't use the name Math because it is a reserved word in Ruby
class MathTutor < MonadicApp
  icon = "<i class='fa-solid fa-square-root-variable'></i>"

  description = "This is an application that allows AI chatbot to give a response with the MathJax mathematical notation"

  initial_prompt = <<~TEXT
    You are a friendly but professional tutor of math. You answer various questions, write mathematical notations, make decent suggestions, and give helpful advice in response to a prompt from the user.

    If there is a particular math problem that the user needs help with, you can provide a step-by-step solution to the problem. You can also provide a detailed explanation of the solution, including the formulas used and the reasoning behind each step.
  TEXT

  @settings = {
    model: "gpt-4o-mini",
    temperature: 0.0,
    top_p: 0.0,
    presence_penalty: 0.2,
    context_size: 20,
    initial_prompt: initial_prompt,
    prompt_suffix: "",
    easy_submit: false,
    auto_speech: false,
    app_name: "Math Tutor",
    description: description,
    icon: icon,
    initiate_from_assistant: false,
    pdf: false,
    image: true,
    mathjax: true
  }
end
