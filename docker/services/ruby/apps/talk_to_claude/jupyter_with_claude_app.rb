# frozen_string_literal: true

require_relative "./claude_helper"

class JupyterWithClaude < MonadicApp
  include ClaudeHelper

  def icon
    "<i class='fa-solid fa-a'></i>"
  end

  def description
    "This is an application that allows Anthropic Claude to create and read/write Jupyter Notebooks"
  end

  def prompt_suffix
    <<~TEXT
      Always use "tool calls" to add Jupyter cells. Do not make a mistake of just showing JSON data for tool calls, but be sure to execute the tool calls properly. If you show object data withtout executing the tool calls, the user will not be able to see the output of the cells in the Jupyter Notebook.
    TEXT
  end

  def initial_prompt
    text = <<~TEXT
      You are an agent that can create and read Jupyter Notebooks. First, launch Jupyter Lab using the `run_jupyter` function with the `run` command and tell the user that the jupyter lab is available at `http://127.0.0.1:8888/lab` and that the user can ask the agent to stop it if needed.

      Next, ask the user if he or she wants a new notebook to be created. If so, create one using the `create_jupyter_notebook` function with the base filename "monadic" and then provide the Notebook file in the form:

      `<a href="http://127.0.0.1:8888/lab/tree/FILENAME" target="_blank" rel="noopener noreferrer">Jupyter Notebook: FILENAME</a>`

      IN the code above, FILENAME is the name of the newly created Jupyter Notebook file (without preceding paths such as 'data/monadic/'). If the user makes a request to add cells before creating a new notebook, let the user know that a new notebook has to be created first.

      Then ask the user for what cells to add to the Jupyter Notebook. You can use the `add_jupyter_cells` function with the ipynb filename and the JSON data of cells each of which is either the "code" type or the "markdown" type. The JSON data must be properly escaped and formatted.

      The `add_jupyter_cells` function will also run the new cells of the Jupyter Notebook and write the output to the notebook, so the user does not have to run the cells manually. If the function finishes successfully, provide the user with the URL or tell the user to refresh the page to see the output if the URL has already been provided.

      If the user just wants to have some information, just respond to the user's request. If the user wants addition of cells to the existing notebook, call the `add_jupyter_cells` function as part of the "tool calls" providing the filename of the existing notebook and the structured data of the cells.

      If the user wants to stop the Jupyter Lab server, use the `run_jupyter` function with the `stop` command to stop the Jupyter Lab server.

      Please make sure the following important points are respected:
      - Include `import japanize-matplotlib` to display Japanese characters in the plots.
      - In case you get error, let the user know the exact error message and terminate the process.
      - When you call a function, make sure to provide the correct parameters as described in the function description.
      - Do not add a cell with the same content as the last cell in the notebook.
      - Basically use English both in the conversation and in the code. If the user uses a language other than English, use it in your response and code, only as much as possible.
    TEXT

    text.strip
  end

  def settings
    {
      "disabled": !CONFIG["ANTHROPIC_API_KEY"],
      "temperature": 0.3,
      "top_p": 0.0,
      "context_size": 100,
      "initial_prompt": initial_prompt,
      "prompt_suffix": prompt_suffix,
      "image_generation": true,
      "sourcecode": true,
      "easy_submit": false,
      "auto_speech": false,
      "mathjax": true,
      "app_name": "▹ Anthropic Claude (Jupyter)",
      "description": description,
      "icon": icon,
      "initiate_from_assistant": false,
      "pdf": false,
      "image": true,
      "toggle": true,
      "jupyter": true,
      "model": "claude-3-5-sonnet-20240620",
      "models": [
        "claude-3-5-sonnet-20240620",
        "claude-3-opus-20240229"
      ],
      "tools": [
        {
          "name": "run_code",
          "description": "Run program code and return the output.",
          "input_schema": {
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
        },
        {
          "name": "lib_installer",
          "description": "Install a library using the package manager. The package manager can be pip or apt. The command is the name of the library to be installed. The `packager` parameter corresponds to the folllowing commands respectively: `pip install`, `apt-get install -y`.",
          "input_schema": {
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
        },
        {
          "name": "run_bash_command",
          "description": "Run a bash command and return the output. The argument to `command` is provided as part of `docker exec -w shared_volume container COMMAND`.",
          "input_schema": {
            "type": "object",
            "properties": {
              "command": {
                "type": "string",
                "description": "Bash command to be executed."
              }
            },
            "required": ["command"]
          }
        },
        {
          "name": "fetch_text_from_file",
          "description": "Fetch the text from a file and return its content.",
          "input_schema": {
            "type": "object",
            "properties": {
              "file": {
                "type": "string",
                "description": "File name or file path"
              }
            },
            "required": ["file"]
          }
        },
        {
          "name": "write_to_file",
          "description": "Write content to a file with the specified filename.",
          "input_schema": {
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
        },
        {
          "name": "run_jupyter",
          "description": "Run Jupyter Lab server and return the URL of the Jupyter Lab.",
          "input_schema": {
            "type": "object",
            "properties": {
              "command": {
                "type": "string",
                "enum": ["run", "stop"],
                "description": "Command to run or stop the Jupyter Lab server."
              }
            },
            "required": ["command"]
          }
        },
        {
          "name": "fetch_web_content",
          "description": "Fetch the content of the web page of the given URL and return it.",
          "input_schema": {
            "type": "object",
            "properties": {
              "url": {
                "type": "string",
                "description": "URL of the web page."
              }
            },
            "required": ["url"]
          }
        },
        {
          "name": "create_jupyter_notebook",
          "description": "Create a Jupyter Notebook and return the URL of the Jupyter Notebook.",
          "input_schema": {
            "type": "object",
            "properties": {
              "filename": {
                "type": "string",
                "description": "Base filename of the Jupyter Notebook."
              }
            },
            "required": ["filename"]
          }
        },
        {
          "name": "add_jupyter_cells",
          "description": "Add cells to the Jupyter Notebook and return the URL of the Jupyter Notebook. The cells need to be provided as a JSON array of objects properly escaped and formatted.",
          "input_schema": {
            "type": "object",
            "properties": {
              "filename": {
                "type": "string",
                "description": "Filename of the Jupyter Notebook."
              },
              "cells": {
                "type": "array",
                "items": {
                  "type": "object",
                  "properties": {
                    "type": {
                      "type": "string",
                      "enum": ["code", "markdown"],
                      "description": "Type of the cell."
                    },
                    "content": {
                      "type": "string",
                      "description": "Content of the cell."
                    }
                  },
                  "required": ["type", "content"]
                }
              }
            },
            "required": ["filename", "cells"]
          }
        },
        {
          "name": "fetch_text_from_office",
          "description": "Fetch the text from the Microsoft Word/Excel/PowerPoint file and return it.",
          "input_schema": {
            "type": "object",
            "properties": {
              "file": {
                "type": "string",
                "description": "File name or file path of the Microsoft Word/Excel/PowerPoint file."
              }
            },
            "required": ["file"]
          }
        }
      ]
    }
  end
end
