# We can't use the name Math because it is a reserved word in Ruby
class MathTutor < MonadicApp
  def icon
    "<i class='fa-solid fa-square-root-variable'></i>"
  end

  def description
    "This is an application that allows AI chatbot to give a response with the MathJax mathematical notation"
  end

  def initial_prompt
    text = <<~TEXT
      You are a friendly but professional tutor of math. You answer various questions, write mathematical notations, make decent suggestions, and give helpful advice in response to a prompt from the user.

      If there is a particular math problem that the user needs help with, you can provide a step-by-step solution to the problem. Your JSON response must consists with `message` and `context` keys. The `message` key should contain the general response message, and the `context` key should contain the context of the response message, including the step-by-step solution to the problem.
    TEXT
    text.strip
  end

  def settings
    {
      "model": "gpt-4o-mini",
      "temperature": 0.0,
      "top_p": 0.0,
      "context_size": 20,
      "initial_prompt": initial_prompt,
      "easy_submit": false,
      "auto_speech": false,
      "app_name": "Math Tutor",
      "description": description,
      "icon": icon,
      "initiate_from_assistant": false,
      "pdf": false,
      "image": true,
      "mathjax": true,
      "monadic": true,
      "response_format": {
        type: "json_schema",
        json_schema: {
          name: "math_tutor_response",
          schema: {
            type: "object",
            properties: {
              message: {
                type: "string",
                description: "The response message from the Math Tutor."
              },
              context: {
                type: "object",
                properties: {
                  steps: {
                    type: "array",
                    items: {
                      type: "object",
                      properties: {
                        explanation: {
                          type: "string",
                          description: "The explanation of the step-by-step solution."
                        }
                      },
                      required: ["explanation"],
                      additionalProperties: false
                    }
                  }
                },
                required: ["steps"],
                additionalProperties: false
              }
            },
            required: ["message", "context"]
          },
          strict: true
        }
      }
    }
  end
end
