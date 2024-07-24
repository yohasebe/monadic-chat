class JupyterNotebook < MonadicApp
  def icon
    "<i class='fas fa-rocket'></i>"
  end

  def description
    "This is an application that allows you to create and read Jupyter Notebooks."
  end

  def initial_prompt
    text = <<~TEXT
      You are an agent that can create and read Jupyter Notebooks. First, launch Jupyter Lab using the `run_jupyter` function with the `run` command. Second, create a new notebook using the `create_jupyter_notebook` function.  Once Jupyter Lab is up and running and a new notebook has been created, provide the user with a URL in the form `<a href="http://127.0.0.1:8888/lab/" target="_blank">Jupyter Lab Notebook</a>`. 

      If you have successfully specified a Jupyter Notebook file, provide the user with the filename of the newly created Jupyter Notebook file in the form `<a href="http://127.0.0.1:8888/lab/tree/FILENAME" target="_blank">Jupyter Notebook: FILENAME</a>` where FILENAME is the name of the newly created Jupyter Notebook file. Rememeber the URL should start with `tree/`.

      Then ask the user for what cells to add to the Jupyter Notebook. You can use the `add_jupyter_cells` function with the ipynb filename and the JSON data of cells in the following format where TYPE is either "code" or "markdown" and CONTENT is the content of the cell, which needs to be properly escaped to be valid JSON:

      ```json
      [
        { "type": TYPE, "content": CONTENT }
      ]
      ```

      The `add_jupyter_cells` function will also run the new cells of the Jupyter Notebook and write the output to the notebook, so the user does not have to run the cells manually. If the function finishes successfully, provide the user with the URL or tell the user to refresh the page to see the output if the URL has already been provided.

      If the user wants to stop the Jupyter Lab server, use the `run_jupyter` function with the `stop` command to stop the Jupyter Lab server.

      Please make sure the following important points are respected:
      - Include `import japanize-matplotlib` to display Japanese characters in the plots.
      - In case you get error, let the user know the exact error message and terminate the process.
      - When you call a function, make sure to provide the correct parameters as described in the function description.
      - Do not add a cell with the same content as the last cell in the notebook.
    TEXT
    text.strip
  end

  def settings
    {
      "model": "gpt-4o",
      "temperature": 0.0,
      "presence_penalty": 0.2,
      "top_p": 0.0,
      "context_size": 100,
      "initial_prompt": initial_prompt,
      "image_generation": true,
      "sourcecode": true,
      "easy_submit": false,
      "auto_speech": false,
      "mathjax": true,
      "app_name": "Jupyter Notebook",
      "description": description,
      "icon": icon,
      "initiate_from_assistant": true,
      "image": true,
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
                  "description": "Program that execute the code (e.g., 'python')"
                },
                "code": {
                  "type": "string",
                  "description": "Program code to be executed."

                },
                "extension": {
                  "type": "string",
                  "description": "File extension of the code when it is temporarily saved to be run (e.g., 'py')"
                }
              },
              "required": ["command", "code", "extension"]
            }
          }
        },
        {
          "type": "function",
          "function":
          {
            "name": "lib_installer",
            "description": "Install a library using the package manager. The package manager can be pip or apt. The command is the name of the library to be installed. The `packager` parameter corresponds to the folllowing commands respectively: `pip install`, `apt-get install -y`.",
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
            "name": "create_jupyter_notebook",
            "description": "Create a Jupyter Notebook and returns its filename."
          }
        },
        {
          "type": "function",
          "function":
          {
            "name": "add_jupyter_cells",
            "description": "Add cells to a Jupyter Notebook.",
            "parameters": {
              "type": "object",
              "properties": {
                "filename": {
                  "type": "string",
                  "description": "Filename of the Jupyter Notebook."
                },
                "cells": {
                  "type": "object",
                  "description": "JSON data of cells in the following format where TYPE is either 'code' or 'markdown' and CONTENT is the content of the cell, which needs to be properly escaped to be valid JSON."
                }
              },
              "required": ["filename", "cells"]
            }
          }
        },
        {
          "type": "function",
          "function":
          {
            "name": "write_to_file",
            "description": "Write content to a file with the specified filename.",
            "parameters": {
              "type": "object",
              "properties": {
                "filename": {
                  "type": "string",
                  "description": "Filename of the file without the file extension."
                },
                "extension": {
                  "type": "string",
                  "description": "File extension of the file."
                },
                "text": {
                  "type": "string",
                  "description": "Content text to be written to the file."
                }
              },
              "required": ["filename", "extension", "text"]
            }
          }
        }
      ]
    }
  end
end
