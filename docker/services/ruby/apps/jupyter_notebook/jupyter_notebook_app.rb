class JupyterNotebook < MonadicApp
  icon = "<i class='fas fa-rocket'></i>"

  description = <<~TEXT
    This is an application that allows OpenAI GPT to create and read/write Jupyter Notebooks.
  TEXT

  prompt_suffix = <<~TEXT
      The function `add_jupyter_cells` needs parameters `filename` and `cells`. The values to `cells` should be adequately escaped as JSON. Take a very good care of escaping the content of the cells properly.
  TEXT

  initial_prompt = <<~TEXT
    You are an agent that can create and read Jupyter Notebooks. First, launch Jupyter Lab using the `run_jupyter` function with the `run` command and tell the user that the jupyter lab is available at `http://127.0.0.1:8888/lab` and that the user can ask the agent to stop it if needed.

    Next, ask the user if he or she wants a new notebook to be created. If so, create one using the `create_jupyter_notebook` function with the base filename "monadic" and then provide the Notebook file in the form:

    `<a href="http://127.0.0.1:8888/lab/tree/FILENAME" target="_blank" rel="noopener noreferrer">Jupyter Notebook: FILENAME</a>`

    Example: `<a href="http://127.0.0.1:8888/lab/tree/monadic_YYYYMMDD_HHMMSS.ipynb`

    IN the code above, FILENAME is the name of the newly created Jupyter Notebook file. If the user makes a request to add cells before creating a new notebook, let the user know that a new notebook has to be created first.

    Then ask the user for what cells to add to the Jupyter Notebook. You can use the `add_jupyter_cells` function with the ipynb filename and the JSON data of cells each of which is either the "code" type or the "markdown" type.

    The `add_jupyter_cells` function will also run the new cells of the Jupyter Notebook and write the output to the notebook, so the user does not have to run the cells manually. If the function finishes successfully, provide the user with the URL or tell the user to refresh the page to see the output if the URL has already been provided.

    If the user just wants to have some information, just respond to the user's request. If the user wants addition of cells to the existing notebook, call the `add_jupyter_cells` function as part of the "tool calls" providing the filename of the existing notebook and the structured data of the cells.

    If the user's request is rather complex, break it down into smaller steps and ask the user for confirmation at each step.

    If the user wants to stop the Jupyter Lab server, use the `run_jupyter` function with the `stop` command to stop the Jupyter Lab server.

    Please make sure the following important points are respected:
    - Include `import japanize-matplotlib` to display Japanese characters in the plots.
    - In case you get error, let the user know the exact error message and terminate the process.
    - When you call a function, make sure to provide the correct parameters as described in the function description.
    - Do not add a cell with the same content as the last cell in the notebook.
    - Basically use English both in the conversation and in the code. If the user uses a language other than English, use it in your response and code, only as much as possible.
  TEXT

  @settings = {
    model: "gpt-4o-2024-08-06",
    temperature: 0.0,
    top_p: 0.0,
    context_size: 100,
    initial_prompt: initial_prompt,
    prompt_suffix: prompt_suffix,
    image_generation: true,
    sourcecode: true,
    easy_submit: false,
    auto_speech: false,
    mathjax: true,
    jupyter: true,
    app_name: "Jupyter Notebook",
    description: description,
    icon: icon,
    initiate_from_assistant: true,
    image: true,
    pdf: false,
    tools: [
      {
        type: "function",
        function:
        {
          name: "run_code",
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
            additionalProperties: false
          }
        },
        strict: true
      },
      {
        type: "function",
        function:
        {
          name: "lib_installer",
          description: "Install a library using the package manager. The package manager can be pip or apt. The command is the name of the library to be installed. The `packager` parameter corresponds to the folllowing commands respectively: `pip install`, `apt-get install -y`.",
          parameters: {
            type: "object",
            properties: {
              command: {
                type: "string",
                description: "Library name to be installed."
              },
              packager: {
                type: "string",
                enum: ["pip", "apt"],
                description: "Package manager to be used for installation."
              }
            },
            required: ["command", "packager"],
            additionalProperties: false
          }
        },
        strict: true
      },
      {
        type: "function",
        function:
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
            additionalProperties: false
          }
        },
        strict: true
      },
      {
        type: "function",
        function:
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
            additionalProperties: false
          }
        },
        strict: true
      },
      {
        type: "function",
        function:
        {
          name: "write_to_file",
          description: "Write content to a file with the specified filename.",
          parameters: {
            type: "object",
            properties: {
              filename: {
                type: "string",
                description: "Filename of the file without the file extension."
              },
              extension: {
                type: "string",
                description: "File extension of the file."
              },
              text: {
                type: "string",
                description: "Content text to be written to the file."
              }
            },
            required: ["filename", "extension", "text"],
            additionalProperties: false
          }
        },
        strict: true
      },
      {
        type: "function",
        function:
        {
          name: "run_jupyter",
          description: "Start a Jupyter Lab server.",
          parameters: {
            type: "object",
            properties: {
              command: {
                type: "string",
                enum: ["run", "stop"],
                description: "Command to start or stop the Jupyter Lab server."
              }
            },
            required: ["command"],
            additionalProperties: false
          }
        },
        strict: true
      },
      {
        type: "function",
        function:
        {
          name: "create_jupyter_notebook",
          description: "Create a Jupyter Notebook and returns its filename.",
          parameters: {
            type: "object",
            properties: {
              filename: {
                type: "string",
                description: "Base filename of the Jupyter Notebook (without the file extension)."
              }
            }
          },
          required: ["filename"],
          additionalProperties: false
        },
        strict: true
      },
      {
        type: "function",
        function:
        {
          name: "add_jupyter_cells",
          description: "Add cells to a Jupyter Notebook.",
          parameters: {
            type: "object",
            properties: {
              filename: {
                type: "string",
                description: "Filename of the Jupyter Notebook."
              },
              cells: {
                type: "array",
                items: {
                  type: "object",
                  properties: {
                    type: {
                      type: "string",
                      enum: ["code", "markdown"],
                      description: "Type of the cell."
                    },
                    content: {
                      type: "string",
                      description: "Content of the cell addequatelly escaped as JSON."
                    }
                  },
                  required: ["type", "content"],
                  additionalProperties: false
                }
              }
            },
            required: ["filename", "cells"],
            additionalProperties: false
          }
        },
        strict: true
      }
    ]
  }
end
