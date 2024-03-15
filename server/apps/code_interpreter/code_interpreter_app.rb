# frozen_string_literal: false

require "tempfile"
require "open3"

class CodeInterpreter < MonadicApp
  def icon
    "<i class='fas fa-terminal'></i>"
  end

  def description
    "This is an application that allows you to run code of Python, Ruby, etc."
  end

  def initial_prompt
    docker_data = File.read(File.expand_path(File.join(__dir__, "..", "..", "docker", "conda", "Dockerfile")))

    text = <<~TEXT
      You are an assistant designed to help users write and run code and visualize data upon from their requests. The user might be learning how to code, working on a project, or just experimenting with new ideas. You support the user every step of the way. Typically, you respond to the user's request by running code and displaying any generated images or text data. Below are detailed instructions on how you do this.

      If the user's messages are in a language other than English, please respond in the same language. If automatic language detection is not possible, kindly ask the user to specify their language at the beginning of their request.

      ### Basic Procedure:

      To execute the code, use the `run_code` function with the command name such as `python` and your code as the parameters. If the code generates images, the function returns the names of the files. Use descriptive file names without any preceding paths for this purpose.

      If the code generates images, save them in the current directory of the code running environment. Use a descriptive file name without any preceding path for this purpose.
      
      ### Error Handling:

      - In case of errors or exceptions during code execution, display the error message to the user. This will help in troubleshooting and improving the code.

      ### Your Environment:

      The following is the dockerfile used to create the environment for running code:

      ```dockerfile
      ${docker_data}
      ```

      ### Request/Response Example 1:

      - The following is a simple example to illustrate how you might respond to a user's request to create a plot.

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

        <div><a href="/data/FILE_NAME">Result</a></div>

    TEXT

    text.strip
  end

  def settings
    {
      "model": "gpt-4-0125-preview",
      "temperature": 0.0,
      "top_p": 0.0,
      "max_tokens": 2000,
      "context_size": 10,
      "initial_prompt": initial_prompt,
      "image_generation": true,
      "sourcecode": true,
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
            "name": "run_code",
            "description": "Run program code and return the output.",
            "parameters": {
              "type": "object",
              "properties": {
                "command": {
                  "type": "string",
                  "description": "Code execution command (e.g., 'python', 'ruby', 'Rscript' etc.)"
                },
                "code": {
                  "type": "string",
                  "description": "Code to be executed."
                },
                "extention": {
                  "type": "string",
                  "description": "File extention of the code (e.g., py, rb, etc.)"
                }
              },
              "required": ["command", "code", "extention"]
            }
          }
        }
      ]
    }
  end

  def run_code(hash)
    code = hash[:code].strip
    command = hash[:command]
    extention = hash[:extention]
    shared_volume = "/monadic/data/"
    if IN_CONTAINER
      data_dir = "/monadic/data/"
    else
      data_dir = File.expand_path(File.join(Dir.home, "monadic", "data"))
    end
      
    conda_container = "monadic-chat-conda-container"

    # create a temporary file inside the data directory
    temp_file = Tempfile.new(["code", ".#{extention}"], data_dir)
    temp_file.write(code)
    temp_file.close
    docker_command =<<~DOCKER
      docker cp #{temp_file.path} #{conda_container}:#{shared_volume}
    DOCKER
    stdout, stderr, status = Open3.capture3(docker_command)
    unless status.success?
      return "Error occurred: #{stderr}"
    end

    local_files1 = Dir[File.join(File.expand_path(File.join(Dir.home, "monadic", "data")), "*")]

    docker_command =<<~DOCKER
      docker exec -w #{shared_volume} #{conda_container} #{command} /monadic/data/#{File.basename(temp_file.path)}
    DOCKER
    stdout, stderr, status = Open3.capture3(docker_command)
    if status.success?
      local_files2 = Dir[File.join(File.expand_path(File.join(Dir.home, "monadic", "data")), "*")]
      new_files = local_files2 - local_files1
      if new_files.length > 0
        new_files = new_files.map { |file| "/data/" + File.basename(file) }
        output = "The code has been executed successfully; Files generated: #{new_files.join(', ')}"
        output += "; Output: #{stdout}" if stdout.strip.length > 0
      else
        output = "The code has been executed successfully"
        output += "; Output: #{stdout}" if stdout.strip.length > 0
      end
      output
    else
      "Error occurred: #{stderr}"
    end
  end
end
