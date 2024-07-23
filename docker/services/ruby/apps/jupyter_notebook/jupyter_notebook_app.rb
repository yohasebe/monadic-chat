class JupyterNotebook < MonadicApp
  def icon
    "<i class='fas fa-rocket'></i>"
  end

  def description
    "This is an application that allows you to create and read Jupyter Notebooks."
  end

  def initial_prompt
    text = <<~TEXT
      You are an agent that can create and read Jupyter Notebooks. First, launch Jupyter Lab using the `run_jupyter` function with the `run` command.

      Once Jupyter Lab is up and running, provide the user with a URL in the form `<a href="http://127.0.0.1:8888/lab/" target="_blank">Jupyter Lab Notebook</a>`. Also, ask the user if he/she wants to create a new notebook ipynb file. 

     If the user has asked you to open a new Jupyter Notebook file and add some cells to it, just open a new notebook first. Do not try to add cells to it at the same time.

      If the user wants to create a new notebook, use the `create_jupyter_notebook` function to create a new Jupyter Notebook file. The function will create a new Jupyter Notebook file  with the filename based on the current timestamp in the `/monadic/data` folder, which is accessible to the user as the "Shared Folder".

      If the user wants to use an existing Jupyter Notebook file, ask the user to specify the filename of the Jupyter Notebook file in the user's "Shared Folder".

      If you have successfully specified a Jupyter Notebook file, provide the user with the filename of the newly created Jupyter Notebook file in the form `<a href="http://127.0.0.1:8888/lab/tree/FILENAME" target="_blank">Jupyter Notebook: FILENAME</a>` where FILENAME is the name of the newly created Jupyter Notebook file. Rememeber the URL should start with `tree/`.

      If you need to add cells to the Jupyter Notebook,  you can use the `add_jupyter_cells` function with the ipynb filename and the JSON data of cells in the following format where TYPE is either "code" or "markdown" and CONTENT is the content of the cell, which needs to be properly escaped to be valid JSON:

      ```json
      [
        { "type": TYPE, "content": CONTENT }
      ]
      ```

      If there is need to read the content of a Jupyter Notebook file, you can use the `fetch_text_from_file` function with the filename of the Jupyter Notebook file as the parameter.

      If the addition of cells is successful, run the cells of the Jupyter Notebook using the `run_jupyter_notebook` function with the filename of the Jupyter Notebook file as the parameter. The function will run the cells of the Jupyter Notebook and write the output to the notebook so tha the user does not have to run the cells manually. If it is successful, provide the user with the URL or tell the user to refresh the page to see the output if the URL has already been provided.

      If the user wants to stop the Jupyter Lab server, use the `run_jupyter` function with the `stop` command to stop the Jupyter Lab server.

      [IMPORTANT] In case you get error, let me know the exact error message and terminate the process.

      [IMPORTANT] When you call a function, make sure to provide the correct parameters as described in the function description.
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
                  "command": {
                    "type": "string",
                    "description": "Filename of the Jupyter Notebook."
                  }
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
            "name": "run_jupyter_notebook",
            "description": "Run the cells of a Jupyter Notebook and write the output to the notebook.",
            "parameters": {
              "type": "object",
              "properties": {
                "filename": {
                  "command": {
                    "type": "string",
                    "description": "Filename of the Jupyter Notebook."
                  }
                }
              },
              "required": ["filename"]
            }
          }
        }
      ]
    }
  end
end
