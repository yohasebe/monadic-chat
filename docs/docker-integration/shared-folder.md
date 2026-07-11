# Shared Folder

When you first start Monadic Chat, a `~/monadic/data` directory is created. This directory is the default Shared Folder for sharing files within Monadic Chat's Docker containers.

Clicking the `Shared Folder` button in the Monadic Chat console will launch the OS's standard file manager and open the Shared Folder.

<!-- SCREENSHOT: Monadic Chat console window showing Shared Folder button and other controls -->

By placing files in this directory, you can access those files within Monadic Chat's Docker containers. The path to the Shared Folder within each Docker container is `/monadic/data`, while the path on your local machine is `~/monadic/data`.

In apps that can execute code (e.g., Code Interpreter app), you can read files from the Shared Folder. When specifying a file, provide only the file name without the directory path.

During the execution of some processes on the AI agent side (using function calling, for example), intermediate files may be saved in the Shared Folder. It is recommended to periodically check and delete unnecessary files.

JupyterLab also starts with `/monadic/data` as its home directory, so the Shared Folder is accessible there as well — see [JupyterLab Integration](./jupyterlab.md).

## The `${SHARED}` Variable

You can refer to the Shared Folder in conversation with `${SHARED}`. The assistant understands `${SHARED}` as the Shared Folder, so you can ask it to read or write files there without typing a full path — for example, *"Save the summary to `${SHARED}/notes.md`"* or *"Read `${SHARED}/data.csv` and chart it."* Monadic Chat expands `${SHARED}` to the correct location automatically, whether the tool runs inside a Docker container (`/monadic/data`) or on your machine (`~/monadic/data`).

Every app can read from and write to the Shared Folder: the assistant has `read_file_from_shared_folder`, `write_file_to_shared_folder`, and `list_files_in_shared_folder` available in every conversation. This lets you exchange files with the assistant in any app — supplying source text to translate, editing a local image, saving a transcript, or referencing a file produced in an earlier turn.

In the assistant's responses, a `${SHARED}` reference is shown as a clickable token: hover over it to see the resolved path, and click it to open that location in your OS file manager.

> Reading and writing files requires a model that supports tool calling. Models without tool-calling support can still hold a conversation but cannot read or write files. To write `${SHARED}` literally without it being treated as a variable, wrap it in backticks.

## Other Interface Variables

In addition to `${SHARED}`, several other variables are available in every conversation. Each one resolves to a piece of runtime information about the current session.

| Variable | Resolves to |
| --- | --- |
| `${SHARED}` | The Shared Folder (`~/monadic/data` on your machine). |
| `${TODAY}` | Today's date in ISO 8601 format (`YYYY-MM-DD`). |
| `${MODEL}` | The AI model currently answering the conversation. |
| `${APP}` | The display name of the current app. |
| `${LANG}` | The language to reply in for the conversation. |

For example, `${TODAY}` resolves to a date such as `2026-05-31`, and `${MODEL}` resolves to the name of the model that is generating the current response.

Like `${SHARED}`, these variables are available by default and can be disabled for a specific app by setting `vocabulary false` in the app definition.

### App-specific variables

A few variables are available only in the apps where they are meaningful, rather than in every conversation:

| Variable | Available in | Resolves to |
| --- | --- | --- |
| `${LAST_GENERATED_IMAGE}` | Image Generator | The filename of the most recent image the assistant generated in the session. |
| `${LAST_UPLOADED_IMAGE}` | Image Generator | The filename of the most recent image the user uploaded in the conversation. |
| `${NOTEBOOK}` | Jupyter Notebook | The filename of the notebook currently in use. |

These appear in the Available Variables panel only while you are in the corresponding app. Like the universal variables, they expand to their value in tool calls and displayed text; before anything has been generated they resolve to nothing, so the literal token is kept.

## How Variables Are Shown

Interface variables fall into two groups, and they are shown differently in the assistant's rendered response:

- **Path-like variables are decorated.** `${SHARED}` stays visible as the `${SHARED}` symbol in the response. Hovering over it shows the resolved path, and clicking it opens that location in your OS file manager. This keeps file paths short and readable while still letting you reach the actual folder.
- **Value-like variables are expanded.** `${TODAY}`, `${MODEL}`, `${APP}`, and `${LANG}` are replaced inline by their resolved value. For example, a sentence written as "Today is `${TODAY}`" is shown as "Today is 2026-05-31".

In tool calls and file paths, every interface variable expands to its real value when the assistant uses it, not only in displayed text. Variables can also be combined. A request like *"Write a report to `${SHARED}/report_${TODAY}.txt`"* writes the file to the Shared Folder with the date filled in, producing a filename such as `report_2026-05-31.txt`.

## Available Variables Panel

The right-side "Monadic Chat Info" panel includes a collapsible "Available Variables" section. It lists the interface variables enabled for the current app, along with a short description of each one and its current resolved value. This lets you see at a glance what is available in the conversation you are in.

The section is collapsed by default; expand it to view the list of variables and their values.

## Examples of Files Saved in the Shared Folder

### Files Generated by Basic Apps

- **Code Interpreter**: Intermediate and result files generated during code execution (e.g., CSV files, text files, image files)
- **Image Generator**: Generated image files (PNG, JPEG, WebP formats)
- **Video Generator**: Generated video files (MP4 format)
- **Jupyter Notebook**: Jupyter Notebook `.ipynb` files
- **Video Describer**: Extracted image frames (PNG format) and audio (MP3 format) from videos
- **Speech Draft Helper**: Generated speech audio files (MP3 format for OpenAI/ElevenLabs, WAV format for Gemini)
- **Syntax Tree**: Generated syntax tree diagrams (SVG format)
- **Concept Visualizer**: Generated concept diagrams (SVG format)
- **Mermaid Grapher**: Generated diagram preview images (PNG format)
- **DrawIO Grapher**: Generated diagram files (.drawio format) and preview images (PNG format)
- **Web Insight**: Captured website screenshots (PNG format)

Files are saved directly in the shared folder with generated filenames that often include timestamps or unique identifiers. It's recommended to periodically clean up unnecessary files.


## Monadic Chat Directory Structure

When Monadic Chat starts for the first time, the following directory structure is automatically created:

```
~/monadic/
├── config/         # Configuration files (env, rbsetup.sh, pysetup.sh)
├── data/           # Shared folder (accessible from containers as /monadic/data)
│   ├── apps/       # Custom applications
│   ├── helpers/    # Helper Ruby files
│   └── scripts/    # Executable scripts accessible from all containers
└── log/            # Log files (server.log, docker_build.log, etc.)
```


The `data` folder is the shared folder that is mounted in all containers. These subfolders are used for organizing custom content when developing additional apps. For information on how to develop additional apps, see [Developing Apps](../advanced-topics/develop_apps.md).

`apps`

This folder stores additional applications beyond the pre-installed basic apps. Each app should reside in its own subfolder within the `apps` directory.

`helpers`

This folder stores helper Ruby files containing functions (methods) used by your apps. These helper files are loaded before the app's recipe file, allowing you to organize and reuse common code across multiple apps.

`scripts`

This folder contains executable scripts (e.g., shell scripts, Python scripts, Ruby scripts) that can be run within any Monadic Chat container. Scripts placed here are automatically made executable and added to the container's PATH, allowing direct execution by name without specifying the full path.

### How User Scripts Work

1. **Location**: Place scripts in `~/monadic/data/scripts` on your host machine
2. **Container Path**: Scripts are available at `/monadic/data/scripts` in containers
3. **Automatic Permissions**: Scripts are automatically made executable before each command execution
4. **Direct Execution**: Call scripts by name only (e.g., `my_script.py` instead of `/monadic/data/scripts/my_script.py`)
5. **Container Support**: Works with Ruby, Python, and other containers

### Example Usage in Apps

```ruby
# Execute a custom Python script
send_command(
  command: "analyze_data.py input.csv output.json",
  container: "python"
)

# Execute a custom Ruby script
send_command(
  command: "process_text.rb document.txt",
  container: "ruby"
)

# Execute a shell script
send_command(
  command: "backup_data.sh",
  container: "python"  # or any container with bash
)
```

### Technical Details

- The `send_command` method in Monadic Chat automatically adds `/monadic/data/scripts` to the PATH environment variable
- Working directory is set to `/monadic/data` when executing commands
- Scripts can access other files in the shared folder using relative paths
- This mechanism allows extending Monadic Chat's functionality without modifying core code
