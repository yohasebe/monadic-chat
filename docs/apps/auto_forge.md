# Auto Forge

Auto Forge builds single-file web applications and command-line tools from your description. The model you chat with plans the work and talks with you, and a code generation model of the same provider writes the code.

Auto Forge is available with OpenAI, Anthropic (Claude), and xAI (Grok). It needs the API key of the provider you use.

## What It Makes

- **Web applications**: one HTML file with the CSS and JavaScript inside it, which runs in the browser without a server and loads nothing from outside
- **Command-line tools**: a standalone script in Python, Ruby, Node.js, or another language suited to the task. On request, Auto Forge also writes a README, a configuration template, or a dependency list (such as `requirements.txt` or `Gemfile`)

Examples of web applications: calculators, to-do lists that keep their data in the browser, timers, drawing canvases, memory games, Markdown editors, and color palette generators. Examples of command-line tools: data converters (CSV, JSON, XML), backup helpers, log analyzers, and file organizers.

## How to Use

1. Select **Auto Forge** under the provider you want to use, and describe what you want to build: its name, what it does, and its features
2. With OpenAI and xAI, Auto Forge first proposes a step-by-step plan and waits for your approval; you can ask for changes before it starts
3. Auto Forge generates the application. Code generation for a complex application can take a few minutes; progress is shown in the chat while it runs
4. Ask for changes to improve it or add features

### Modifying and Starting Over

To change an application, ask for the changes using the same application name. Auto Forge updates the latest version of that project. To build it again from scratch under the same name, ask for a fresh start; a new project folder is created.

To see the projects you have made, ask Auto Forge to list them.

## Testing Web Applications

Auto Forge can open a generated web application in Chrome in the Selenium container and report:
- JavaScript errors and console warnings
- Results of trying the forms, buttons, and other interactive elements
- Load time, DOM ready time, and render time
- A screenshot of the page

With OpenAI and xAI, this check runs as part of building a web application. With Claude, it runs when you ask for it.

## Where Projects Are Saved

Projects are saved in `~/monadic/data/auto_forge/`, one folder per project, named after the project with the date and time:

```text
auto_forge/
├── TodoApp_20260127_143022/
│   └── index.html
├── Calculator_20260127_151234/
│   └── index.html
├── runtimes-lister_20260928_234449/
│   ├── runtimes_lister.py
│   └── README.md
└── ...
```

Project names can contain characters of any language.

## Tips

1. Describe the functions you want in detail
2. Start simple and add features step by step
3. Give each project a descriptive name

## Troubleshooting

- **No files appear yet**: code generation can take a few minutes for a complex application. Wait until the progress in the chat finishes
- **"Selenium container is not running"**: the Selenium container starts with Monadic Chat. Check the console for errors at startup, and restart Monadic Chat
- **"Project not found"**: ask Auto Forge to list the projects and use the exact project name
