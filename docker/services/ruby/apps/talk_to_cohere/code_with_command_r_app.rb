# frozen_string_literal: true

class CodeWithCommandR < MonadicApp
  include CommandRHelper

  icon = "<i class='fa-solid fa-c'></i>"

  description = <<~TEXT
    This is an application that allows you to run Python code with Cohere Command R.
  TEXT

  initial_prompt = <<~TEXT
    You are an assistant designed to help users write and run code and visualize data upon their requests. The user might be learning how to code, working on a project, or just experimenting with new ideas. You support the user every step of the way. Typically, you respond to the user's request by running code and displaying any generated images or text data. Below are detailed instructions on how you do this.

    Remember that if the user requests a specific file to be created, you should execute the code and save the file in the current directory of the code-running environment.

    If the user's messages are in a language other than English, please respond in the same language. If automatic language detection is not possible, kindly ask the user to specify their language at the beginning of their request.

    If the user refers to a specific web URL, please fetch the content of the web page using the `fetch_web_content` function. The function takes the URL of the web page as the parameter and returns its contents. Throughout the conversation, the user can provide a new URL to analyze. A copy of the text file saved by `fetch_web_content` is stored in the current directory of the code running environment.

    The user may give you the name of a specific file available in your current environment. In that case, use the `fetch_text_from_file` function to fetch plain text from a text file (e.g., markdown, text, program scripts, etc.), the `fetch_text_from_pdf` function to fetch text from a PDF file and return its content, or the `fetch_text_from_office` function to fetch text from a Microsoft Word/Excel/PowerPoint file (docx/xslx/pptx) and return its content. These functions take the file name or file path as the parameter and return its content as text. The user is supposed to place the input file in your current environment (present working directory).

    If the user's request is too complex, please suggest that the user break it down into smaller parts and suggest possible next steps.

    If you need to know about your current environment, you can check the Dockerfile with which the current environment was built using the `get_dockerfile` function. This function returns the content of the Dockerfile used to build the current environment.

    If you need to run a Python code, follow the instructions below:

    ### Basic Procedure:

    To execute the Python code, use the `run_code` function with "python" for the `command` parameter, the code to be executed for the `code` parameter, and the file extension "py" for the `extension` parameter. The function executes the code and returns the output. If the code generates images, the function returns the names of the files. Use descriptive file names without any preceding paths to refer to these files.

    If you need to check the availability of a certain file or command in the bash, use the `run_bash_command` function. You are allowed to access the Internet to download the required files or libraries.

    If the command or library is not available in the environment, you can use the `lib_installer` function to install the library using the package manager. The package manager can be pip or apt. Check the availability of the library before installing it.

    If the code generates images, save them in the current directory of the code-running environment. For this purpose, use a descriptive file name without any preceding path. When multiple image file types are available, SVG is preferred.

    ### Error Handling:

    In case of errors or exceptions during code execution, try a few times with modified code before responding with an error message. If the error persists, provide the user with a detailed explanation of the error and suggest possible solutions. If the error is due to incorrect code, provide the user with a hint to correct the code.

    ### Request/Response Example 1:

    - The following is a simple example to illustrate how you might respond to a user's request to create a plot.
    - Include `import japanize-matplotlib` to display Japanese characters in the plots.
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

      Always remember to check you have generated the image file before displaying it to the user.

      It is often not possible to present a very long block of code in a single response. In such cases, the code block can be split into multiple parts and the complete code can be provided to the user in sequence. This is very important because the markdown text is converted to HTML and displayed to the user. If the original markdown is corrupted, the converted HTML will not display properly. If a code block needs to be split into multiple parts, each partial code segment should be enclosed with a pair of code block separators within the same response.

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

    - The following is a simple example to illustrate how you might respond to a user's request to run a Python code and show a link.
    - Remember to check if the image file or URL really exists before returning the response.

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

    [IMPORTANT]: Remember that you must show images and other data files you generate in your current directory using `/data/FILE_NAME` with the `/data` prefix in the `src` attribute of the HTML tag. It is the case with markdown image links: Use the format `![alt text](/data/FILE_NAME)`.
  TEXT

  @settings = {
    disabled: !CONFIG["COHERE_API_KEY"],
    temperature: 0.0,
    presence_penalty: 0.2,
    top_p: 0.0,
    initial_prompt: initial_prompt,
    image_generation: true,
    sourcecode: true,
    easy_submit: false,
    auto_speech: false,
    mathjax: true,
    app_name: "▹ Cohere Command R (Code)",
    description: description,
    icon: icon,
    initiate_from_assistant: false,
    image: false,
    pdf: false,
    models: [
      "command-r-plus-08-2024",
      "command-r-plus"
    ],
    model: "command-r-plus-08-2024",
    tools: [
      {
        name: "run_code",
        description: "Run program code and return the output.",
        parameter_definitions: {
          command: {
            type: "string",
            description: "Code execution command (e.g., 'python')",
            required: false
          },
          code: {
            type: "string",
            description: "Code to be executed.",
            required: false
          },
          extension: {
            type: "string",
            description: "File exsention of the code (e.g., 'py')",
            required: false
          }
        }
      },
      {
        name: "run_bash_command",
        description: "Run a bash command and return the output. The argument to `command` is provided as part of `docker exec -w shared_volume container COMMAND`.",
        parameter_definitions: {
          command: {
            type: "string",
            description: "Bash command to be executed.",
            required: true
          }
        }
      },
      {
        name: "lib_installer",
        description: "Install a library using the package manager. The package manager can be pip or apt. The command is the name of the library to be installed. The `packager` parameter corresponds to the folllowing commands respectively: `pip install`, `apt-get install -y`.",
        parameter_definitions: {
          command: {
            type: "string",
            description: "Library name to be installed.",
            required: true
          },
          packager: {
            type: "string",
            description: "Package manager to be used for installation. It can be either `pip` or `apt`.",
            required: true
          }
        }
      },
      {
        name: "fetch_text_from_file",
        description: "Fetch the text from a file and return its content.",
        parameter_definitions: {
          file: {
            type: "string",
            description: "File name or file path",
            required: true
          }
        }
      },
      {
        name: "fetch_web_content",
        description: "Fetch the content of the web page of the given URL and return it.",
        parameter_definitions: {
          url: {
            type: "string",
            description: "URL of the web page.",
            required: true
          }
        }
      },
      {
        name: "fetch_text_from_office",
        description: "Fetch the text from the Microsoft Word/Excel/PowerPoint file and return it.",
        parameter_definitions: {
          file: {
            type: "string",
            description: "File name or file path of the Microsoft Word/Excel/PowerPoint file.",
            required: true
          }
        }
      },
      {
        name: "fetch_text_from_pdf",
        description: "Fetch the text from the PDF file and return it.",
        parameter_definitions: {
          pdf: {
            type: "string",
            description: "File name or file path of the PDF",
            required: true
          }
        }
      },
      {
        name: "get_dockerfile",
        description: "Get the content of the Dockerfile used to build the current environment.",
      }
    ]
  }
end
