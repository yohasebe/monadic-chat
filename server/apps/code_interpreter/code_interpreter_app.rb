# frozen_string_literal: true

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

      If the user refers to a specific web URL, please fetch the content of the web page using the `fetch_web_content` function. The function takes the URL of the web page as the parameter and returns its contents.

      If the user's request is too complex, please suggest that the user break it down into smaller parts, suggesting possible next steps.

      ### Basic Procedure:

      To execute the code, use the `run_code` function with the command name such as `python` and your code as the parameters. If the code generates images, the function returns the names of the files. Use descriptive file names without any preceding paths for this purpose.

      If you need to check bash command to check the availability of a certain file or command, use the `run_bash_command` function. You are allowed to access the internet to download the required files or libraries.

      If the command or library is not available in the environment, you can use the `lib_installer` function to install the library using the package manager. The package manager can be conda, pip, apt, gem, or npm.

      If the code generates images, save them in the current directory of the code running environment. Use a descriptive file name without any preceding path for this purpose. When there are multiple image file types available, SVG is preferred.

      If the user asks for it, you can also start a Jupyter Lab server using the `run_jupyter(command)` function. If successful, you should provide the user with the URL to access the Jupyter Lab server in a way that the user can easily click on it and the new tab opens in the browser using `<a href="URL" target="_blank">Jupyter Lab</a>`.
      
      ### Error Handling:

      - In case of errors or exceptions during code execution, display the error message to the user. This will help in troubleshooting and improving the code.

      ### Your Environment:

      The following is the dockerfile used to create the environment for running code:

      ```dockerfile
      ${docker_data}
      ```

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
        },
        {
          "type": "function",
          "function":
          {
            "name": "lib_installer",
            "description": "Install a library using the package manager. The package manager can be conda, pip, apt, gem, or npm. The command is the name of the library to be installed. The `packager` parameter corresponds to the folllowing commands respectively: `conda install -y`, `pip install`, `apt-get install -y`, `gem install`, `npm install -g`.",
            "parameters": {
              "type": "object",
              "properties": {
                "command": {
                  "type": "string",
                  "description": "Library name to be installed."
                },
                "packager": {
                  "type": "string",
                  "enum": ["conda", "pip", "apt", "gem", "npm"],
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
            "description": "Fetch the content of a web page and save it in the current directory.",
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
        }
      ]
    }
  end

  def run_code(hash)
    begin
      code = hash[:code].to_s.strip rescue ""
      command = hash[:command].to_s.strip rescue ""
      extention = hash[:extention].to_s.strip rescue ""
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
    rescue StandardError => e
      "Error occurred: The code could not be executed."
    end
  end

  def lib_installer(hash)
    begin
      command = hash[:command].to_s.strip rescue ""
      packager = hash[:packager].to_s.strip rescue ""
      install_command = case packager
                        when "conda"
                          "conda install -y #{command}"
                        when "pip"
                          "pip install #{command}"
                        when "apt"
                          "apt-get install -y #{command}"
                        when "gem"
                          "gem install #{command}"
                        when "npm"
                          "npm install -g #{command}"
                        else
                          "echo 'Invalid packager'"
                        end

      shared_volume = "/monadic/data/"
      conda_container = "monadic-chat-conda-container"
      docker_command =<<~DOCKER
        docker exec -w #{shared_volume} #{conda_container} #{install_command}
      DOCKER
      stdout, stderr, status = Open3.capture3(docker_command)
      if status.success?
        "The library #{command} has been installed successfully.\n\nLOG: #{stdout}"
      else
        "Error occurred: #{stderr}"
      end
    rescue StandardError => e
      "Error occurred: The library could not be installed."
    end
  end

  def run_jupyter(hash)
    begin
      command = hash[:command].to_s.strip rescue ""
      shared_volume = "/monadic/data/"
      conda_container = "monadic-chat-conda-container"
      command = "bash -c '/monadic/run_jupyter.sh #{command}'"
      docker_command =<<~DOCKER
        docker exec -w #{shared_volume} #{conda_container} #{command}
      DOCKER
      stdout, stderr, status = Open3.capture3(docker_command)
      if status.success?
        <<~MESSAGE
        Success: Access Jupter Lab at 127.0.0.1:8888/lab

        #{stdout}
        MESSAGE
      else
        "Error occurred: #{stderr}"
      end
    rescue StandardError => e
      "Error occurred: The Jupyter Lab server could not be started."
    end
  end

  def run_bash_command(hash)
    begin
      command = hash[:command].to_s.strip rescue ""
      shared_volume = "/monadic/data/"
      conda_container = "monadic-chat-conda-container"
      docker_command =<<~DOCKER
        docker exec -w #{shared_volume} #{conda_container} #{command}
      DOCKER
      stdout, stderr, status = Open3.capture3(docker_command)
      if status.success?
        stdout
      else
        "Error occurred: #{stderr}"
      end
    rescue StandardError => e
      "Error occurred: The bash command could not be executed."
    end
  end

  def fetch_web_content(hash)
    begin
      url = hash[:url].to_s.strip rescue ""
      shared_volume = "/monadic/data/"
      conda_container = "monadic-chat-conda-container"
      command = "bash -c '/monadic/web_content_fetcher.py --url \"#{url}\" --filepath \"#{shared_volume}\" --mode \"md\" '"
      docker_command =<<~DOCKER
        docker exec -w #{shared_volume} #{conda_container} #{command}
      DOCKER
      stdout, stderr, status = Open3.capture3(docker_command)
      if status.success?
        # get a filename (/saved to: (.+\.md)/) embedded in the stdout
        filename = stdout.match(/saved to: (.+\.md)/).to_a[1]
        contents = File.read(filename)
        contents
      else
        "Error occurred: #{stderr}"
      end
    rescue StandardError => e
      "Error occurred: #{stderr}"
    end
  end
end
