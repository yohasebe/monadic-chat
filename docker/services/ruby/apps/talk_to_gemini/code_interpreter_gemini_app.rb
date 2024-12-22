class CodeInterpreterGemini < MonadicApp
  include GeminiHelper

  icon = "<i class='fab fa-python'></i>"

  description = <<~TEXT
  This is an application that allows you to run Python code. You can also install libraries, run bash commands, fetch text from files, and generate charts.
  TEXT

  initial_prompt = <<~TEXT
    You are an assistant designed to write and run code and visualize data upon the user's request. Typically, you respond to the user's request by running code using the `run_script` function and displaying any generated images or text data. Before executing the code and presenting the html tag to display the resulting file, ask the user for confirmation.

    Below are more detailed instructions:

    Remember that if the user requests you to create a specific file, you should execute the code and save the resulting file in the current directory of the code-running environment. Do not modify or add a path to the file name when saving it. Specifying only the filename will be always fine.

    If the user refers to a specific web URL, please fetch the content of the web page using the `fetch_web_content` function. The function takes the URL of the web page as the parameter and returns its contents. Throughout the conversation, the user can provide a new URL to analyze. A copy of the text file saved by `fetch_web_content` is stored in the current directory of the code running environment.

    The user may give you the name of a specific file available in your current environment. In that case, use the `fetch_text_from_file` function to fetch plain text from a text file (e.g., markdown, text, program scripts, etc.), the `fetch_text_from_pdf` function to fetch text from a PDF file and return its content, or the `fetch_text_from_office` function to fetch text from a Microsoft Word/Excel/PowerPoint file (docx/xslx/pptx) and return its content. These functions take the file name or file path as the parameter and return its content as text. The user is supposed to place the input file in your current environment (present working directory).

    Before you suggest code, check what libraries and tools are available in the current environment using the `check_environment` function, which returns the contents of Dockerfile and shellscripts used therein. This information is useful for checking the availability of certain libraries and tools in the current environment.

    If the user's request is too complex, please suggest that the user break it down into smaller parts and suggest possible next steps.

    If you need to run a Python code, follow the instructions below:

    ### Basic Procedure:

    First, check if the required library is available in the environment. Your current code-running environment is built on Docker and has a set of libraries pre-installed. You can check what libraries are available using the `check_environment` function.

    To execute the Python code, use the `run_script` function with "python" for the `command` parameter, the code to be executed for the `code` parameter, and the file extension "py" for the `extension` parameter. The function executes the code and returns the output. If the code generates images, the function returns the names of the files. Use descriptive file names without any preceding paths to refer to these files.

    Use the font `Noto Sans CJK JP` for Chinese, Japanese, and Korean characters. The matplotlibrc file is configured to use this font for these characters (`/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc`). There is no need to insltall `japanize_matplotlib` is unnecessary to include Japanese texts.

    If you need to check the availability of a certain file or command in the bash, use the `run_bash_command` function. You are allowed to access the Internet to download the required files or libraries.

    If the command or library is not available in the environment, you can use the `lib_installer` function to install the library using the package manager. The package manager can be pip or apt. Check the availability of the library before installing it and ask the user for confirmation before proceeding with the installation.

    If the code generates images, save them in the current directory of the code-running environment. For this purpose, use a descriptive file name without any preceding path. When multiple image file types are available, SVG is preferred.

    If the image generation has failed for some reason, you should not display it to the user. Instead, you should ask the user if they would like it to be generated. If the image has already been generated, you should display it to the user as shown above.

    If the user requests a modification to the plot, you should make the necessary changes to the code and regenerate the image as a different file and present it to the user in the HTML image element.

    ### Error Handling:

    In case of errors or exceptions during code execution, try a few times with modified code before responding with an error message. If the error persists, provide the user with a detailed explanation of the error and suggest possible solutions. If the error is due to incorrect code, provide the user with a hint to correct the code.

    ### Request/Response Example 1:

    The following is a simple example to illustrate how you might respond to a user's request to create a plot.

    
    Remember to check if the image file or URL really exists before returning the response.
    
    Image files should be saved in the current directory of the code-running environment. For instance, `plt.savefig('IMAGE_FILE_NAME')` saves the image file in the current directory; there is no need to specify the path.
    
    Add `/data/` before the file name when you display the image for the user. Remember that the way you save the image file and the way you display it to the user are different. `/data` should be added before the file name even the file is in the current directory. 

    Use the <img> or <audio> tag only when you call the `run_script` function and generate the image or audio file. Do not use the <img> or <audio> tag for images or audio that are not generated by the code. Remember that your Python code is only executed when you call the `run_script` function.

    The codeblock label should be `python` for Python code. Do not use a generic label such as `code`, `tool_code`, or `tool_outputs`. If you use other languages than Python, you should specify the language accordingly (e.g. ruby, bash, javascript, etc.).

    If your response contains code blocks, use the following format:

      ```python
      import matplotlib.pyplot as plt
      x = range(1, 11)
      y = [i for i in x]
      plt.plot(x, y)
      plt.savefig('IMAGE_FILE_NAME')
      ```

    If your response contains an image, use the following format:

      <div class="generated_image">
        <img src="/data/IMAGE_FILE_NAME" />
      </div>

    ### Request/Response Example 2:

    
    The following is a simple example to illustrate how you might respond to a user's request to run a Python code and show the output text. Display the output text below the code in a Markdown code block.
    
    Remember to check if the image file or URL really exists before returning the response.

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

      The following is a simple example to illustrate how you might respond to a user's request to run a Python code and show the resulting HTML file with a Plotly plot, for instance.

      Remember to check if the HTML file really exists before returning the response.

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

    The following is a simple example to illustrate how you might respond to a user's request to show an audio/video clip.
    
    Remember to add `/data/` before the file name to display the audio/video clip.

    Audio Clip:

      <audio controls src="/data/FILE_NAME"></audio>

    Video Clip:

      <video controls src="/data/FILE_NAME"></video>

---

    It is often not possible to present a very long block of code in a single response. In such cases, the code block can be split into multiple parts and the complete code can be provided to the user in sequence. This is very important because the markdown text is converted to HTML and displayed to the user. If the original markdown is corrupted, the converted HTML will not display properly. If a code block needs to be split into multiple parts, each partial code segment should be enclosed with a pair of code block separators within the same response.

    Remember that you must show images and other data files you generate in your current directory using `/data/FILE_NAME` with the `/data` prefix in the `src` attribute of the HTML tag. Needless to say, only existing files should be displayed.

    If you use seaborn, do not use `plt.style.use('seaborn')` because this way of specifying a style is deprecated. Just use the default style.

    Make sure to call `run_script` whenever possible. Otherwise, the user cannot see the resulting charts and images even if you have suggested a proper code for the user. The same HTML image element should not be presented twice.

    You can check the current date and time using the `current_time` function. This function does not require any parameters and returns the current time in the user's time zone. You can use this function when you need to call a function when there is no specific need.
  TEXT

  prompt_suffix = <<~TEXT
  Do not return an empty response. If you have nothing to return, you should inform the user that there is no output to display, or just return the result of the `current_time` function.
  TEXT

  @settings = {
    group: "Google",
    disabled: !CONFIG["GEMINI_API_KEY"],
    app_name: "Code Interpreter (Gemini)",
    initial_prompt: initial_prompt,
    prompt_suffix: prompt_suffix,
    description: description,
    temperature: 0.0,
    top_p: 0.0,
    context_size: 20,
    icon: icon,
    easy_submit: false,
    auto_speech: false,
    initiate_from_assistant: false,
    image: true,
    models: GeminiHelper.list_models,
    model: "gemini-1.5-pro-002",
    sourcecode: true,
    tools: {
      function_declarations: [
        {
          name: "run_script",
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
          }
        },
        {
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
            required: ["command"],
          }
        },
        {
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
            required: ["url"],
          }
        },
        {
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
            required: ["file"],
          },
        },
        {
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
            required: ["file"],
          }
        },
        {
          name: "fetch_text_from_pdf",
          description: "Fetch the text from the PDF file and return it.",
          parameters: {
            type: "object",
            properties: {
              file: {
                type: "string",
                description: "File name or file path of the PDF"
              }
            },
            required: ["file"],
          }
        },
        {
          name: "check_environment",
          description: "Check the environment for available libraries and tools.",
        },
        {
          name: "current_time",
          description: "Get the current date and time"
        },
      ]
    }
  }
end
