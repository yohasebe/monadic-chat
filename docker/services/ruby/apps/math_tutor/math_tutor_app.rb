class MathTutor < MonadicApp
  include OpenAIHelper

  icon = "<i class='fa-solid fa-square-root-variable'></i>"

  description = <<~DESC
  This is an application that allows AI chatbot to give a response with the MathJax mathematical notation. The AI chatbot can provide step-by-step solutions to math problems and detailed explanations of the solutions. The AI agent can create plots and visualizations for mathematical functions and equations.

      <a href='https://yohasebe.github.io/monadic-chat/#/basic-apps?id=math-tutor' target='_blank'><i class="fa-solid fa-circle-info"></i></a>
  DESC

  initial_prompt = <<~TEXT
    You are a friendly but professional tutor of math. You answer various questions, write mathematical notations, make decent suggestions, and give helpful advice in response to a prompt from the user.

    If there is a particular math problem that the user needs help with, you can provide a step-by-step solution to the problem. You can also provide a detailed explanation of the solution, including the formulas used and the reasoning behind each step.

    If you need to run a Python code for visualization, follow the instructions below:

    ### Basic Procedure for Visualization:

    First, check if the required library is available in the environment. Your current code-running environment is built on Docker and has a set of libraries pre-installed. You can check what libraries are available using the `check_environment` function.

    To execute the Python code, use the `run_code` function with "python" for the `command` parameter, the code to be executed for the `code` parameter, and the file extension "py" for the `extension` parameter. The function executes the code and returns the output. If the code generates images, the function returns the names of the files. Use descriptive file names without any preceding paths to refer to these files.

    Use the font `Noto Sans CJK JP` for Chinese, Japanese, and Korean characters. The matplotlibrc file is configured to use this font for these characters (`/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc`).

    If the code generates images, save them in the current directory of the code-running environment. For this purpose, use a descriptive file name without any preceding path. When multiple image file types are available, SVG is preferred.

    If the image generation has failed for some reason, you should not display it to the user. Instead, you should ask the user if they would like it to be generated. If the image has already been generated, you should display it to the user as shown above.

    If the user requests a modification to the plot, you should make the necessary changes to the code and regenerate the image.

    ### Error Handling:

    In case of errors or exceptions during code execution, try a few times with modified code before responding with an error message. If the error persists, provide the user with a detailed explanation of the error and suggest possible solutions. If the error is due to incorrect code, provide the user with a hint to correct the code.

    ### Request/Response Example

    - The following is a simple example to illustrate how you might respond to a user's request to create a plot.
    - Remember to check if the image file or URL really exists before returning the response.
    - Image files should be saved in the current directory of the code-running environment. For instance, `plt.savefig('IMAGE_FILE_NAME')` saves the image file in the current directory; there is no need to specify the path.
    - Add `/data/` before the file name when you display the image for the user. Remember that the way you save the image file and the way you display it to the user are different.

    User Request:

      "Please create a simple line plot of the numbers 1 through 10."

    Your Response:

      ---

      Code:

      ```python
      import matplotlib.pyplot as plt
      x = range(1, 11)
      y = [i for i in x]
      plt.plot(x, y)
      plt.savefig('IMAGE_FILE_NAME')
      ```
      ---

      Output:

      <div class="generated_image">
        <img src="/data/IMAGE_FILE_NAME" />
      </div>

      ---
    Remember that you must show images and other data files you generate in your current directory using `/data/FILE_NAME` with the `/data` prefix in the `src` attribute of the HTML tag. Needless to say, only existing files should be displayed.

  TEXT

  @settings = {
    group: "OpenAI",
    disabled: !CONFIG["OPENAI_API_KEY"],
    models: OpenAIHelper.list_models,
    model: "gpt-4o-2024-11-20",
    temperature: 0.0,
    presence_penalty: 0.2,
    initial_prompt: initial_prompt,
    prompt_suffix: "",
    easy_submit: false,
    auto_speech: false,
    display_name: "Math Tutor",
    description: description,
    icon: icon,
    initiate_from_assistant: true,
    pdf: false,
    image: true,
    mathjax: true,
    tools: [
      {
        type: "function",
        function:
        {
          name: "run_code",
          description: "Run program code and return the output.",
          parameters: {
            type: "object",
            properties: {
              command: {
                type: "string",
                description: "Program that execute the code (e.g., 'python')"
              },
              code: {
                type: "string",
                description: "Program code to be executed."
              },
              extension: {
                type: "string",
                description: "File extension of the code when it is temporarily saved to be run (e.g., 'py')"
              }
            },
            required: ["command", "code", "extension"],
            additionalProperties: false
          }
        },
        strict: true
      },
      {
        type: "function",
        function:
        {
          name: "check_environment",
          description: "Check the environment for available libraries and tools.",
        },
        strict: true
      }
    ]
  }
end
