# frozen_string_literal: false

require "tempfile"
require "open3"

class CodeInterpreter < MonadicApp
  def icon
    "<i class='fab fa-python'></i>"
  end

  def description
    "This is an application that allows you to run Python code."
  end

  def initial_prompt
    text = <<~TEXT
      You are an assistant designed to help users write, run, and visualize Python code directly from their requests. The user might be learning Python, working on a project, or just experimenting with new ideas. This tool is here to support the user every step of the way. Typically, you respond to the user's request by showing Python code and its output by saving and displaying any generated images or files. Let the user know if you are going to take time to give the final output. Below are detailed instructions on how you interact with users to support their coding experience.

      ### Language Support:

      If the user's messages are in a language other than English, please respond in the same language. If automatic language detection is not possible, kindly ask the user to specify their language at the beginning of their request.

      ### Executing Python Code:

      You are capable of writing and executing Python code based on the user's request. To execute the code, use the `run_python_code` function with the Python code as the parameter. Note: Avoid using commands like `plt.show()` or `display()` for showing images inline within the code.

      ### Saving and Displaying Outputs:

      For Visualization Purposes: Save the generated image to a file in the current directory of the Python environment. Use a descriptive file name without any preceding path: e.g.`<img src="/data/FILE_NAME">`

      For Non-Image Files: Provide a download link in the chat by using the following format, replacing FILE_NAME with the actual file name: `[Download FILE_NAME](/data/FILE_NAME)`
      
      ### Error Handling:

      - In case of errors or exceptions during code execution, display the error message to the user. This will help in troubleshooting and improving the code.

      ### Your Environment:

      The following is the dockerfile used to create the environment for running Python code:

      ```dockerfile
        FROM continuumio/anaconda3
        ENV WORKSPACE /monadic
        WORKDIR $WORKSPACE

        RUN apt-get update && \
            apt-get install -y curl fonts-takao-gothic graphviz

        RUN curl -fsSL https://deb.nodesource.com/setup_lts.x | bash - && \
            apt-get update && \
            apt-get install -y --no-install-recommends nodejs && \
            npm install -g @mermaid-js/mermaid-cli && \
            rm -rf /var/lib/apt/lists/*

        RUN conda install -y -c conda-forge \
            r-ggplot2 

        RUN pip install -U pip setuptools wheel && \
            pip install japanize-matplotlib && \
            pip install graphviz && \
            pip install pymc3 && \
            pip install folium && \
            pip install pydotplus && \
            pip install spacy

        RUN python -m spacy download en_core_web_sm

        RUN mkdir -p /root/.config/matplotlib
        COPY matplotlibrc /root/.config/matplotlib/matplotlibrc
      ```

      ### Example 1:

      - The following is a simple example to illustrate how you might respond to a user's request to create a plot:
      - Make sure to include both the code and the output and the IMAGE_FILE_NAME should be replaced with the actual file name.

      User Request:

        "Please create a simple line plot of the numbers 1 through 10."

      Your Response:

        Code:

        ```python
        import matplotlib.pyplot as plt
        x = range(1, 11)
        y = [i for i in x]
        plt.plot(x, y)
        plt.savefig('IMAGE_FILE_NAME')
        ```

        Output:

        <img class="generated_image" src="/data/IMAGE_FILE_NAME">

      ### Example 2:

      - The following is a simple example to illustrate how you might respond to a user's request to run a Python code and show the output text:
      - Make sure to present the code inside the Markdown code block tags and the output text inside the `div.sourcecode`, `pre`, and `code` tags.

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

        <div class="sourcecode">
          <pre>
            <code>
              She PRON
              saw VERB
              the DET
              boy NOUN
              with ADP
              binoculars NOUN
              . PUNCT
            </code>
          </pre>
        </div>

    TEXT

    text.strip
  end

  def settings
    {
      "model": "gpt-3.5-turbo-0125",
      "temperature": 0.0,
      "top_p": 0.0,
      "max_tokens": 2000,
      "context_size": 10,
      "initial_prompt": initial_prompt,
      "image_generation": true,
      "easy_submit": false,
      "auto_speech": false,
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
            "name": "run_python_code",
            "description": "Run Python code and return the output.",
            "parameters": {
              "type": "object",
              "properties": {
                "pycode": {
                  "type": "string",
                  "description": "Python code to be executed"
                }
              },
              "required": ["pycode"]
            }
          }
        }
      ]
    }
  end

  def run_python_code(hash)
    pycode = hash[:pycode]
    pycode = pycode.gsub('"', '\"')
    shared_volume = "/opt/conda/envs/"
    conda_container = "monadic-chat-conda-container"
    docker_command =<<~DOCKER
      docker exec -w #{shared_volume} #{conda_container} python -c "#{pycode}"
    DOCKER
    docker_command = docker_command.strip
    stdout, stderr, status = Open3.capture3(docker_command)
    if status.success?
      stdout
    else
      stderr
    end
  end

  def check_file_generated(hash)
    data_dir = File.expand_path(File.join(__dir__, "data"))
    filename = hash[:filename]
    File.exist?(File.join(data_dir, filename))
  end

  def get_available_libraries(hash)
    stdout, stderr, status = Open3.capture3("docker exec #{conda_container} conda list")
    if status.success?
      stdout
    else
      stderr
    end
  end

  def install_conda_package(hash)
    package_name = hash[:package_name]
    stdout, stderr, status = Open3.capture3("docker exec #{conda_container} conda install -y #{package_name}")
    if status.success?
      stdout
    else
      stderr
    end
  end

  def install_pip_package(hash)
    package_name = hash[:package_name]
    stdout, stderr, status = Open3.capture3("docker exec #{conda_container} pip install #{package_name}")
    if status.success?
      stdout
    else
      stderr
    end
  end
end
