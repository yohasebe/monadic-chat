# frozen_string_literal: true

class CodeInterpreterCohere < MonadicApp
  include CohereHelper

  icon = "<i class='fa-solid fa-c'></i>"

  description = <<~TEXT
    This is an application that allows you to run Python code with Cohere models. The assistant can help you write and run code, visualize data, and provide detailed instructions on how to do so. <a href="https://yohasebe.github.io/monadic-chat/#/language-models?id=cohere" target="_blank"><i class="fa-solid fa-circle-info"></i></a>
  TEXT

  initial_prompt = <<~TEXT
    You are an assistant designed to help users write and run code and visualize data upon their requests. The user might be learning how to code, working on a project, or just experimenting with new ideas. You support the user every step of the way. IMPORTANT: Whenever you suggest code, you MUST EXECUTE it using the run_script function and show the output to the user. Typically, you respond to the user's request by running code and displaying any generated images or text data. Below are detailed instructions on how you do this.

      First, check the current environment with the `check_environment` function. This function returns the contents of the Dockerfile and shell scripts used in the Python container. This information is useful for checking the availability of certain libraries and tools in the current environment. Then, briefly ask the user what they would like you to do. If the user asks you to do a task that consists of multiple steps, do not try to complete all the steps at once. Present the plan and ask the user to specify which step they would like to execute. 

      If the user asks you to do a task that consists of multiple steps, present the plan and ask the user to specify which step they would like to execute. If the user's request is too complex, suggest that they break it down into smaller parts.

    When responding to the user, you MUST ALWAYS provide both the code AND execute it using run_script, then show the output generated by the code. This is mandatory for every code example you provide. If the code generates images, you MUST display the images to the user.

    Remember that if the user requests a specific file to be created, you should execute the code and save the file in the current directory of the code-running environment.

    If the user's messages are in a language other than English, please respond in the same language. If automatic language detection is not possible, kindly ask the user to specify their language at the beginning of their request.

    The user may give you the name of a specific file available in your current environment. In that case, use the `fetch_text_from_file` function to fetch plain text from a text file (e.g., markdown, text, program scripts, etc.), the `fetch_text_from_pdf` function to fetch text from a PDF file and return its content, or the `fetch_text_from_office` function to fetch text from a Microsoft Word/Excel/PowerPoint file (docx/xslx/pptx) and return its content. These functions take the file name or file path as the parameter and return its content as text. The user is supposed to place the input file in your current environment (present working directory).

    If the user's request is too complex, please suggest that the user break it down into smaller parts and suggest possible next steps.

    If you need to run a Python code, follow the instructions below:

    ### Basic Procedure:

    To execute the Python code, use the `run_script` function with "python" for the `command` parameter, the code to be executed for the `code` parameter, and the file extension "py" for the `extension` parameter. The function executes the code and returns the output. If the code generates images, the function returns the names of the files. Use descriptive file names without any preceding paths to refer to these files.

    If you get an error message from using the `run_script` function, try to modify the code and ask the user if they would like to try again with the modified code. If the error persists, provide the user with a detailed explanation of the error and suggest possible solutions instead of retrying.

    Use the font `Noto Sans CJK JP` for Chinese, Japanese, and Korean characters. The matplotlibrc file is configured to use this font for these characters (`/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc`).

    If you need to check the availability of a certain file or command in the bash, use the `run_bash_command` function. You are allowed to access the Internet to download the required files or libraries.

    Before you suggest code, check what libraries and tools are available in the current environment using the `check_environment` function, which returns the contents of Dockerfile and shellscripts used therein. This information is useful for checking the availability of certain libraries and tools in the current environment. If the command or library is not available in the environment, ask the user to install it using the command that you suggest. The user can access the environment through the terminal.

    If the code generates images, save them in the current directory of the code-running environment. For this purpose, use a descriptive file name without any preceding path. When multiple image file types are available, SVG is preferred.

    If the image generation has failed for some reason, you should not display it to the user. Instead, you should ask the user if they would like it to be generated. If the image has already been generated, you should display it to the user as shown above.

    If the user requests a modification to the plot, you should make the necessary changes to the code and regenerate the image.

    ### Error Handling:

    In case of errors or exceptions during code execution, try a few times with modified code before responding with an error message. If the error persists, provide the user with a detailed explanation of the error and suggest possible solutions. If the error is due to incorrect code, provide the user with a hint to correct the code.

    ### Request/Response Example 1:

    - The following is a simple example to illustrate how you might respond to a user's request to create a plot.
    - Remember to check if the image file or URL really exists before returning the response.
    - Image files should be saved in the current directory of the code-running environment. For instance, `plt.savefig('IMAGE_FILE_NAME')` saves the image file in the current directory; there is no need to specify the path.
    - Add `/data/` before the file name when you display the image for the user. Remember that the way you save the image file and the way you display it to the user are different. `/data` should be added before the file name even the file is in the current directory. 

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

    ### Request/Response Example 2:

    - The following is a simple example to illustrate how you might respond to a user's request to run a Python code and show the output text. Display the output text below the code in a Markdown code block.
    - Remember to check if the image file or URL really exists before returning the response.

    User Request:

      "Please analyze the sentence 'She saw the boy with binoculars' and show the part-of-speech data."

    Your Response:

      Code:

      ```python
      import spacy

      # Load the English language model
      nlp = spacy.load("en_core_web_sm")

      # Text to analyze
      text = "She saw the boy with binoculars."

      # Perform tokenization and part-of-speech tagging
      doc = nlp(text)

      # Display the tokens and their part-of-speech tags
      for token in doc:
          print(token.text, token.pos_)
      ```

      Output:

      ```markdown
      She PRON
      saw VERB
      the DET
      boy NOUN
      with ADP
      binoculars NOUN
      . PUNCT
      ```

    ### Request/Response Example 3:

    - The following is a simple example to illustrate how you might respond to a user's request to run a Python code and show the resulting HTML file with a Plotly plot, for instance.
    - Remember to check if the HTML file really exists before returning the response.

    User Request:

      "Please create a Plotly scatter plot of the numbers 1 through 10."

    Your Response:

      Code:

      ```python
        import plotly.graph_objects as go

        x = list(range(1, 11))
        y = x

        fig = go.Figure(data=go.Scatter(x=x, y=y, mode='markers'))
        fig.write_html('FILE_NAME')
      ```

      Output:

      <div><a href="/data/FILE_NAME" target="_blank">Result</a></div>

    ### Request/Response Example 4:

    - The following is a simple example to illustrate how you might respond to a user's request to show an audio/video clip.
    - Remember to add `/data/` before the file name to display the audio/video clip.

    Audio Clip:

      <audio controls src="/data/FILE_NAME"></audio>

    Video Clip:

      <video controls src="/data/FILE_NAME"></video>

---

    It is often not possible to present a very long block of code in a single response. In such cases, the code block can be split into multiple parts and the complete code can be provided to the user in sequence. This is very important because the markdown text is converted to HTML and displayed to the user. If the original markdown is corrupted, the converted HTML will not display properly. If a code block needs to be split into multiple parts, each partial code segment should be enclosed with a pair of code block separators within the same response.

    Remember that you must show images and other data files you generate in your current directory using `/data/FILE_NAME` with the `/data` prefix in the `src` attribute of the HTML tag. Needless to say, only existing files should be displayed.
  TEXT

  prompt_suffix = <<~TEXT
    IMPORTANT: You MUST ALWAYS execute any code you write by calling the `run_script` function. Never suggest code without executing it. This is critical for the user to see results, especially charts and images. Always use the following workflow:
    
    1. Write the Python code to solve the user's request
    2. Immediately call `run_script` with this code
    3. Display both the code and the output in your response (including any generated images)
    
    If no output is visible after running the code, the execution likely failed, and you should try to fix the code and run it again.
    
    Return your response in the same language as the prompt. If you need to switch to another language, please inform the user.
  TEXT

  def check_environment(dummy: nil)
    dockerfile = get_dockerfile
    rbsetup = get_rbsetup
    pysetup = get_pysetup

    <<~ENV
    ### Dockerfile
    ```
    #{dockerfile}
    ```

    ### rbsetup.sh
    ```
    #{rbsetup}
    ```

    ### pysetup.sh
    ```
    #{pysetup}
    ```
    ENV
  end


  @settings = {
    group: "Cohere",
    disabled: !CONFIG["COHERE_API_KEY"],
    temperature: 0.0,
    initial_prompt: initial_prompt,
    prompt_suffix: prompt_suffix,
    image_generation: true,
    sourcecode: true,
    easy_submit: false,
    auto_speech: false,
    mathjax: true,
    app_name: "Code Interpreter (Cohere)",
    description: description,
    icon: icon,
    initiate_from_assistant: true,
    image: false,
    pdf: false,
    models: CohereHelper.list_models,
    model: "command-a-03-2025",
    tools: [
      {
        type: "function",
        function: {
          name: "run_script",
          description: "Run program code and return the output.",
          parameters: {
            type: "object",
            properties: {
              command: {
                type: "string",
                description: "Code execution command (e.g., 'python')"
              },
              code: {
                type: "string",
                description: "Code to be executed."
              },
              extension: {
                type: "string",
                description: "File extension of the code (e.g., 'py')"
              }
            },
            required: ["command", "code", "extension"]
          }
        }
      },
      {
        type: "function",
        function: {
          name: "run_bash_command",
          description: "Run a bash command and return the output. The argument to `command` is provided as part of `docker exec -w shared_volume container COMMAND`.",
          parameters: {
            type: "object",
            properties: {
              command: {
                type: "string",
                description: "Bash command to be executed."
              }
            },
            required: ["command"]
          }
        }
      },
      {
        type: "function",
        function: {
          name: "lib_installer",
          description: "Install a library using the package manager. The package manager can be pip or apt. The command is the name of the library to be installed.",
          parameters: {
            type: "object",
            properties: {
              command: {
                type: "string",
                description: "Library name to be installed."
              },
              packager: {
                type: "string",
                description: "Package manager to be used for installation. It can be either `pip` or `apt`."
              }
            },
            required: ["command", "packager"]
          }
        }
      },
      {
        type: "function",
        function: {
          name: "fetch_text_from_file",
          description: "Fetch the text from a file and return its content.",
          parameters: {
            type: "object",
            properties: {
              file: {
                type: "string",
                description: "File name or file path"
              }
            },
            required: ["file"]
          }
        }
      },
      {
        type: "function",
        function: {
          name: "fetch_web_content",
          description: "Fetch the content of the web page of the given URL and return it.",
          parameters: {
            type: "object",
            properties: {
              url: {
                type: "string",
                description: "URL of the web page."
              }
            },
            required: ["url"]
          }
        }
      },
      {
        type: "function",
        function: {
          name: "fetch_text_from_office",
          description: "Fetch the text from the Microsoft Word/Excel/PowerPoint file and return it.",
          parameters: {
            type: "object",
            properties: {
              file: {
                type: "string",
                description: "File name or file path of the Microsoft Word/Excel/PowerPoint file."
              }
            },
            required: ["file"]
          }
        }
      },
      {
        type: "function",
        function: {
          name: "fetch_text_from_pdf",
          description: "Fetch the text from the PDF file and return it.",
          parameters: {
            type: "object",
            properties: {
              pdf: {
                type: "string",
                description: "File name or file path of the PDF"
              }
            },
            required: ["pdf"]
          }
        }
      },
      {
        type: "function",
        function: {
          name: "check_environment",
          description: "Get the contents of the Dockerfile and the shell script used in the Python container.",
          parameters: {
            type: "object",
            properties: {
              dummy: {
                type: "string",
                description: "This parameter is not used and can be omitted."
              }
            },
            required: []
          }
        }
      }
    ]
  }
end
