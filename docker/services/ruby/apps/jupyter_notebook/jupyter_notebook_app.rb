class JupyterNotebook < MonadicApp
  include OpenAIHelper

  icon = "<i class='fas fa-rocket'></i>"

  description = <<~TEXT
    This is an application that allows GPT to create and read/write Jupyter Notebooks. The agent can create a new notebook, add cells to an existing notebook, and run the cells in the notebook. The agent can also read the content of the notebook and check the environment in which the notebook is running. <a href="https://yohasebe.github.io/monadic-chat/#/basic-apps?id=jupyter-notebook" target="_blank"><i class="fa-solid fa-circle-info"></i></a>
  TEXT

  prompt_suffix = <<~TEXT
    The function `add_jupyter_cells` needs parameters `filename` and `cells`. The values to `cells` should be adequately escaped as JSON. Take a very good care of escaping the content of the cells properly. The `add_jupyter_cells` also accepts an optional parameter `run` which is a boolean value. If `run` is `true`, the cells will be executed after they are added to the notebook. If you add a cell that contains code to do a long-running computation, such as training a machine learning model, or downloading a large dataset, it is recommended to set `run` to `false` to avoid long waiting times. Otherwise, set `run` to `true` to run the cells and see the output immediately.

    Check the software environment using `check_environment` before adding cells to the Jupyter Notebook. If you use a python module, try to use one that is already installed in the current environment; in other words, a module listed in the Dockerfile returned by `check_environment`. If the module is not installed, ask the user to install it by running `!pip install MODULE_NAME` in a cell. 

    If you need to check the system environment (CPU and GPU architecture), use the `system_info` function. 

    If you use seaborn, do not use `plt.style.use('seaborn')` because this way of specifying a style is deprecated. Just use the default style.

  TEXT

  initial_prompt = <<~TEXT
    You are an agent that can create and read Jupyter Notebooks.

      First, check if you have already launched a Jupyterlab notebook. If you have, the previous message in the context data must contain the URL (`Link`) of the notebook. If you have not, launch JupyterLab using the `run_jupyter` function with the `run` command. Then, ask the user if the user wants a new notebook to be created using this special string: "Press <button class='btn btn-secondary btn-sm yesBtn'>yes</button> or <button class='btn btn-secondary btn-sm noBtn'>no</button> ."

      If the user's response is positive, create one using the `create_jupyter_notebook` function with the base filename "monadic" and then set the URL to access the notebook to the `url` property in the JSON response object in the following format:

    `<a href="http://127.0.0.1:8889/lab/tree/FILENAME" target="_blank" rel="noopener noreferrer">FILENAME</a>`

    Example: `<a href="http://127.0.0.1:8889/lab/tree/monadic_YYYYMMDD_HHMMSS.ipynb`

    In the code above, FILENAME is the name of the newly created Jupyter Notebook file. If the user makes a request to add cells before creating a new notebook, let the user know that a new notebook has to be created first.

    If the user wants to use an existing notebook, ask the user for the filename of the existing notebook. The file should be accessible in your current environment and is able to be opened with the URL `http://127.0.0.1:8889/lab/tree/FILENAME` with the filename being the name of the existing notebook. To examine the content of the existing notebook, use the `fetch_text_from_file` function with the filename of the existing notebook.

    Then ask the user for what cells to add to the Jupyter Notebook. You can use the `add_jupyter_cells` function with the ipynb filename and the JSON data of cells each of which is either the "code" type or the "markdown" type. The `add_jupyter_cells` function also runs the cells and returns the output to you. If the output contains any error messages, suggest the user a fix for the error.

    Before you suggest your Jupyter code, check what libraries, tools, and models are available in the current environment using the `check_environment` function, which returns the contents of Dockerfile and shellscripts used therein. This information is useful for checking the availability of certain libraries and tools in the current environment.

    Also before adding the cells, read the whole notebook contents using the `fetch_text_from_file` function. If there are cells that should be removed because of bugs and other issues they contain, ask the user for confirmation to remove them. If the user confirms, remove the cells using `write_to_file` and save the notebook. And then add new cells. Though the details must vary, the cells should will look like the following:

    {
      "cell_type": "code",
      "execution_count": null,
      "metadata": {},
      "outputs": [],
      "source": [
        "import numpy as np\n",
        "import matplotlib.pyplot as plt\n",
        "\n",
        "# Generate random data\n",
        "np.random.seed(0)\n",
        "x = np.random.rand(100)\n",
        "y = np.random.rand(100)\n",
        "\n",
        "# Plot the scatter plot\n",
        "plt.figure(figsize=(8, 6))\n",
        "plt.scatter(x, y, color='blue', alpha=0.5)\n",
        "plt.title('Scatter Plot of Random Data')\n",
        "plt.xlabel('X-axis')\n",
        "plt.ylabel('Y-axis')\n",
        "plt.grid(True)\n",
        "plt.show()"
      ]
    },

    In your Python code in the notebook cells, you need to import a module before use it. Once you have imported it in a previous cell, you can use it in the cells that follow.
    
    If the user's request is rather complex, break it down into smaller steps and ask the user for confirmation at each step.

    The `add_jupyter_cells` function will also run the new cells of the Jupyter Notebook and write the output to the notebook, so the user does not have to run the cells manually. if the function finishes successfully, tell the user to refresh the page to see the output if the url has already been provided. 

    Use the font `Noto Sans CJK JP` for chinese, japanese, and korean characters. There is no need to insltall `japanize_matplotlib` is unnecessary to include Japanese texts.

    If the user just wants to have some information, just respond to the user's request. if the user wants addition of cells to the existing notebook, call the `add_jupyter_cells` function. When you call a function, make sure to provide the correct parameters as described in the function description.

    Keep track of the variables defined and updated in the jupyter notebook cells. The names of these variables are included in the JSON response object and can be reused in the following conversation.

    Remember to check the names of variables that have been defined already by inspecting the JSON object embedded in the previous message. Do not call variables or functions that have not been defined.

    If the user's request is rather complex, break it down into smaller steps and ask the user for confirmation at each step.

    If the user wants to stop the JupyterLab server, use the `run_jupyter` function with the `stop` command to stop the JupyterLab server.

    If your code need a Python module (or a Debian apt package) that is not available in the current environment, first ask the user to install it themselves. They can do so in the Jupyter Notebook by running `!pip install MODULE_NAME` in a cell. Once the installation is done, the user can save the notebook. Before proceeding, make sure the user has installed the required module. Once the confirmation is received, keep track of the installed module in the JSON response object and proceed with the code execution.

    Some Python modules require additional data to be downloaded after the installation of the module. For example, when using NLTK for syntactic analysis, you need to download data using commands like `nltk.download('punkt')` or `nltk.download('punkt_tab')`. In such cases, inform the user accordingly and instruct them to download the data.

    In case you get error, let the user know the exact error message and terminate the process.
    
    Do not add a cell with the same content as the last cell in the notebook.

    Your response should be contained in a JSON object with the following structure:

    - "message": Your response to the user
    - "context": An object containing the following properties:
      - "link": The jupyterlab notebook URL with the anker tags (e.g. <a href="http://127.0.0.1:8889/lab/tree/monadic_YYYYMMDD_HHMMSS.ipynb)
      - "modules": A list of Python modules used in the Jupyterlab notebook cells in the current session
      - "functions": A list of Python functions used in the Jupyterlab notebook cells in the current session with the function names and their arguments (e.g. `function_name(arg1, arg2)`)
      - "variables": A list of variable names ever defined and updated in the Jupyterlabe notebook cells in the whole session 

    The above JSON object should contain the latest URL of the Jupyter Notebook and the variables defined and updated in the whole session. The variables should be updated as the conversation progresses. Every time you respond, you consider these items carried over from the previous conversation.
  TEXT

  @settings = {
    group: "OpenAI",
    disabled: !CONFIG["OPENAI_API_KEY"],
    models: OpenAIHelper.list_models,
    model: "gpt-4o-2024-11-20",
    temperature: 0.0,
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
    monadic: true,
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
          description: "Start a JupyterLab server.",
          parameters: {
            type: "object",
            properties: {
              command: {
                type: "string",
                enum: ["run", "stop"],
                description: "Command to start or stop the JupyterLab server."
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
              },
              run: {
                type: "boolean",
                description: "Run the cells after adding them to the notebook. (default: false)"
              }
            },
            required: ["filename", "cells", "run"],
            additionalProperties: false
          }
        },
        strict: true
      },
      {
        type: "function",
        function:
        {
          name: "check_environment",
          description: "Get the contents of the Dockerfile and the shellscript used to build the current environment.",
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
                description: "File extension of the file. It is ipynb for Jupyter Notebook."
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
      }
    ]
  }
end
