# Shared Folder

When you first start Monadic Chat, a `~/monadic/data` directory is created. This directory is the default Shared Folder for sharing files within Monadic Chat's Docker containers.

The `Shared Folder` button in the Monadic Chat console (or **Open → Open Shared Folder**) opens the Shared Folder in your OS file manager.

<!-- SCREENSHOT: Monadic Chat console window showing Shared Folder button and other controls -->

By placing files in this directory, you can access those files within Monadic Chat's Docker containers. The path to the Shared Folder within each Docker container is `/monadic/data`, while the path on your local machine is `~/monadic/data`.

In apps that can execute code (e.g., Code Interpreter app), you can read files from the Shared Folder. A file at the top of the Shared Folder can be given by its name alone; for a file in a subfolder, give its path relative to the Shared Folder.

During the execution of some processes on the AI agent side (using function calling, for example), intermediate files may be saved in the Shared Folder. It is recommended to periodically check and delete unnecessary files.

JupyterLab also starts in `/monadic/data`, so the Shared Folder is available there as well — see [JupyterLab Integration](./jupyterlab.md).

## The `${SHARED}` Variable

You can refer to the Shared Folder in conversation with `${SHARED}`. The assistant understands `${SHARED}` as the Shared Folder, so you can ask it to read or write files there without typing a full path — for example, *"Save the summary to `${SHARED}/notes.md`"* or *"Read `${SHARED}/data.csv` and chart it."* When the assistant uses `${SHARED}` in a tool call, Monadic Chat replaces it with the Shared Folder's actual location.

Every app can read and write text files in the Shared Folder: the assistant has `read_file_from_shared_folder`, `write_file_to_shared_folder`, and `list_files_in_shared_folder` in every app (Live Conversation has its own set of tools instead). This lets you exchange files with the assistant in any app — supplying source text to translate, saving a transcript, or referring to a file produced in an earlier turn. These tools do not write into the `apps`, `helpers`, `scripts`, and `services` folders.

In the assistant's responses, a `${SHARED}` reference is shown as a clickable token: hover over it to see the path. In the Monadic Chat window, clicking it opens that location in your OS file manager; in an external browser, clicking it copies the path.

> Reading and writing files requires a model that supports tool calling. Models without tool-calling support can still hold a conversation but cannot read or write files.

## Other Interface Variables

In addition to `${SHARED}`, several other variables are available in every conversation. Each one resolves to a piece of runtime information about the current session.

| Variable | Resolves to |
| --- | --- |
| `${SHARED}` | The Shared Folder (`~/monadic/data` on your machine). |
| `${TODAY}` | Today's date in ISO 8601 format (`YYYY-MM-DD`). |
| `${MODEL}` | The AI model currently answering the conversation. |
| `${APP}` | The display name of the current app. |
| `${LANG}` | The language to reply in for the conversation (the interface language when the conversation language is Automatic). |

For example, `${TODAY}` resolves to a date such as `2026-05-31`, and `${MODEL}` resolves to the name of the model that is generating the current response.

Like `${SHARED}`, these variables are available in every app by default.

### App-specific variables

A few variables are available only in the apps where they are meaningful, rather than in every conversation:

| Variable | Available in | Resolves to |
| --- | --- | --- |
| `${LAST_GENERATED_IMAGE}` | Image Generator | The filename of the most recent image the assistant generated in the session. |
| `${LAST_UPLOADED_IMAGE}` | Image Generator | The filename of the most recent image the user uploaded in the conversation. |
| `${NOTEBOOK}` | Jupyter Notebook | The filename of the notebook currently in use. |

These appear in the Available Variables panel only while you are in the corresponding app. Like the universal variables, they expand to their value in tool calls and displayed text. Until there is a value (before any image or notebook exists), the token is kept as written.

## How Variables Are Shown

Interface variables fall into two groups, and they are shown differently in the assistant's rendered response:

- **Path-like variables are decorated.** `${SHARED}` stays visible as the `${SHARED}` symbol in the response, with the path on hover (see above).
- **Value-like variables are expanded.** `${TODAY}`, `${MODEL}`, `${APP}`, `${LANG}`, and the app-specific variables are replaced inline by their value. For example, a sentence written as "Today is `${TODAY}`" is shown as "Today is 2026-05-31".

In tool calls and file paths, every interface variable expands to its real value when the assistant uses it, not only in displayed text. Variables can also be combined. A request like *"Write a report to `${SHARED}/report_${TODAY}.txt`"* writes the file to the Shared Folder with the date filled in, producing a filename such as `report_2026-05-31.txt`.

## Available Variables Panel

The right-side "Monadic Chat Info" panel includes a collapsible "Available Variables" section. It lists the interface variables enabled for the current app, along with a short description of each one and its current resolved value. This lets you see at a glance what is available in the conversation you are in.

The section is collapsed by default; expand it to view the list of variables and their values.

## Examples of Files Saved in the Shared Folder

### Files Generated by Basic Apps

- **Code Interpreter**: Intermediate and result files generated during code execution (e.g., CSV files, text files, image files)
- **Image Generator**: Generated images (PNG; OpenAI can also save JPEG or WebP)
- **Video Generator**: Generated videos (MP4)
- **Jupyter Notebook**: Notebooks (`.ipynb`)
- **Video Describer**: Frames extracted from a video (PNG, in a `frames_<timestamp>` folder) and its audio (MP3)
- **Speech Draft Helper**: Speech audio (MP3; with Gemini, the format the API returns, usually WAV)
- **Syntax Tree**: Syntax tree diagrams (SVG)
- **Concept Visualizer**: Concept diagrams (SVG and PNG)
- **DrawIO Grapher**: Diagram files (`.drawio`) and previews (PNG)
- **Web Insight**: Web page screenshots (PNG)

Most files are saved at the top of the shared folder, with file names that include a timestamp or an identifier. Clean up files you no longer need from time to time.


## Monadic Chat Directory Structure

Monadic Chat creates these folders when it starts, if they do not exist:

```text
~/monadic/
├── config/         # Configuration files (env, rbsetup.sh, pysetup.sh)
├── data/           # Shared folder (accessible from containers as /monadic/data)
│   ├── apps/       # Custom applications
│   ├── helpers/    # Helper Ruby files
│   ├── scripts/    # Executable scripts for the Python container
│   └── services/   # Definitions of your own Docker containers
├── log/            # Log files (server.log, docker_build.log, etc.)
└── state/          # Records Monadic Chat keeps for itself (do not edit)
```


The `data` folder is the shared folder, mounted in the Ruby, Python, Selenium, and Extractor containers. Its `apps`, `helpers`, and `services` folders are read-only inside the containers. These subfolders hold your own additions to Monadic Chat. For information on how to develop additional apps, see [Developing Apps](../advanced-topics/develop_apps.md).

`apps`

This folder stores additional applications beyond the pre-installed basic apps. Each app should reside in its own subfolder within the `apps` directory.

`helpers`

This folder stores helper Ruby files containing functions (methods) used by your apps. These helper files are loaded before the app's recipe file, allowing you to organize and reuse common code across multiple apps.

`services`

This folder holds the definitions of your own Docker containers. See [Adding Docker Containers](../advanced-topics/adding-containers.md).

`scripts`

This folder contains executable scripts (e.g., shell scripts, Python scripts) that run in the Python container. Scripts placed here are automatically made executable and added to the container's PATH, allowing direct execution by name without specifying the full path. The folder comes last on PATH, so a script named like a system command (`python3`, `bash`) does not replace that command; give scripts names of their own. They do not run on the Ruby side (`container: "ruby"`), which runs only the scripts that come with Monadic Chat.

### How User Scripts Work

1. **Location**: Place scripts in `~/monadic/data/scripts` on your host machine
2. **Container Path**: Scripts are available at `/monadic/data/scripts` in containers
3. **Automatic Permissions**: Scripts are made executable before each command runs
4. **Direct Execution**: Call scripts by name only (e.g., `my_script.py` instead of `/monadic/data/scripts/my_script.py`)
5. **Container Support**: Works with the Python container, not with the Ruby side

### Example Usage in Apps

```ruby
# Execute a custom Python script
send_command(
  command: "analyze_data.py input.csv output.json",
  container: "python"
)

# Execute another custom Python script
send_command(
  command: "process_text.py document.txt",
  container: "python"
)

# Execute a shell script
send_command(
  command: "backup_data.sh",
  container: "python"
)
```

Commands run with `/monadic/data` as the working directory, so scripts can reach other files in the shared folder with relative paths. For writing apps that call scripts, see [Developing Apps](../advanced-topics/develop_apps.md).
