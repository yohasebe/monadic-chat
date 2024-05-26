# frozen_string_literal: true

class CodeInterpreter < MonadicApp
  def icon
    "<i class='fas fa-terminal'></i>"
  end

  def description
    "This is an application that allows you to run Python code"
  end

  def initial_prompt
    text = <<~TEXT
      You are an assistant designed to help users write and run code and visualize data upon from their requests. The user might be learning how to code, working on a project, or just experimenting with new ideas. You support the user every step of the way. Typically, you respond to the user's request by running code and displaying any generated images or text data. Below are detailed instructions on how you do this.

      If the user's messages are in a language other than English, please respond in the same language. If automatic language detection is not possible, kindly ask the user to specify their language at the beginning of their request.

      If the user refers to a specific web URL, please fetch the content of the web page using the `fetch_web_content` function. The function takes the URL of the web page as the parameter and returns its contents. Throughout the conversation, the user can provide a new URL to analyze.

      A copy of the text file saved by `fetch_web_content` is stored in the current directory of the code running environment. Use the `fetch_text_from_file` function to fetch the text from the file and return its content. Give the base file name as the parameter to the function.

      If the user's request is too complex, please suggest that the user break it down into smaller parts, suggesting possible next steps.

      If you need to run a Python code, follow the instructions below:

      ### Basic Procedure:

      To execute the code, use the `run_code` function with the command name such as `python` and your code as the parameters. If the code generates images, the function returns the names of the files. Use descriptive file names without any preceding paths for this purpose.

      If you need to check bash command to check the availability of a certain file or command, use the `run_bash_command` function. You are allowed to access the internet to download the required files or libraries.

      If the command or library is not available in the environment, you can use the `lib_installer` function to install the library using the package manager. The package manager can be pip or apt. Check the availability of the library before installing it.

      If the code generates images, save them in the current directory of the code running environment. Use a descriptive file name without any preceding path for this purpose. When there are multiple image file types available, SVG is preferred.

      If the user asks for it, you can also start a Jupyter Lab server using the `run_jupyter(command)` function. If successful, you should provide the user with the URL to access the Jupyter Lab server in a way that the user can easily click on it and the new tab opens in the browser using `<a href="URL" target="_blank">Jupyter Lab</a>`.
      
      ### Error Handling:

      - In case of errors or exceptions during code execution, display the error message to the user. This will help in troubleshooting and improving the code.

      ### Request/Response Example 1:

      - The following is a simple example to illustrate how you might respond to a user's request to create a plot.
      - Remember to check if the image file or URL really exists before returning the response. 

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

      - The following is a simple example to illustrate how you might respond to a user's request to run a Python code and show the output text. Display the lutput text below the code in a Markdown code block.
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

      - The following is a simple example to illustrate how you might respond to a user's request to show a audio/video clip.

      Audio Clip:

        <audio controls src="/data/FILE_NAME"></audio>

      Video Clip:

        <video controls src="/data/FILE_NAME"></video>

    TEXT

    text.strip
  end

  def settings
    {
      "model": "gpt-4o",
      "temperature": 0.0,
      "presence_penalty": 0.2,
      "top_p": 0.0,
      "context_size": 20,
      "initial_prompt": initial_prompt,
      "image_generation": true,
      "sourcecode": true,
      "easy_submit": false,
      "auto_speech": false,
      "mathjax": true,
      "app_name": "Code Interpreter",
      "description": description,
      "icon": icon,
      "initiate_from_assistant": false,
      "pdf": false,
      "tools": [
        {
          "type": "function",
          "function":
          {
            "name": "run_code",
            "description": "Run program code and return the output.",
            "parameters": {
              "type": "object",
              "properties": {
                "command": {
                  "type": "string",
                  "description": "Code execution command (e.g., 'python')"
                },
                "code": {
                  "type": "string",
                  "description": "Code to be executed."
                },
                "extention": {
                  "type": "string",
                  "description": "File extention of the code (e.g., 'py')"
                }
              },
              "required": ["command", "code", "extention"]
            }
          }
        },
        {
          "type": "function",
          "function":
          {
            "name": "lib_installer",
            "description": "Install a library using the package manager. The package manager can be pip or apt. The command is the name of the library to be installed. The `packager` parameter corresponds to the folllowing commands respectively: ``pip install`, `apt-get install -y`.",
            "parameters": {
              "type": "object",
              "properties": {
                "command": {
                  "type": "string",
                  "description": "Library name to be installed."
                },
                "packager": {
                  "type": "string",
                  "enum": ["pip", "apt"],
                  "description": "Package manager to be used for installation."
                }
              },
              "required": ["command", "packager"]
            }
          }
        },
        {
          "type": "function",
          "function":
          {
            "name": "run_bash_command",
            "description": "Run a bash command and return the output. The argument to `command` is provided as part of `docker exec -w shared_volume container COMMAND`.",
            "parameters": {
              "type": "object",
              "properties": {
                "command": {
                  "type": "string",
                  "description": "Bash command to be executed."
                }
              },
              "required": ["command"]
            }
          }
        },
        {
          "type": "function",
          "function":
          {
            "name": "run_jupyter",
            "description": "Start a Jupyter Lab server.",
            "parameters": {
              "type": "object",
              "properties": {
                "command": {
                  "type": "string",
                  "enum": ["run", "stop"],
                  "description": "Command to start or stop the Jupyter Lab server."
                }
              },
              "required": ["command"]
            }
          }
        },
        {
          "type": "function",
          "function":
          {
            "name": "fetch_web_content",
            "description": "Fetch the content of the web page of the given URL and return it.",
            "parameters": {
              "type": "object",
              "properties": {
                "url": {
                  "type": "string",
                  "description": "URL of the web page."
                }
              },
              "required": ["url"]
            }
          }
        },
        {
          "type": "function",
          "function":
          {
            "name": "fetch_text_from_file",
            "description": "Fetch the text from a file and return its content.",
            "parameters": {
              "type": "object",
              "properties": {
                "file": {
                  "type": "string",
                  "description": "File name or file path"
                }
              },
              "required": ["file"]
            }
          }
        }
      ]
    }
  end
end
