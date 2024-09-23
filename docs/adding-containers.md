# Adding Docker Containers

## How to Add Containers

To make a new Docker container available, create a new folder in `~/monadic/data/services` and place the following files inside it:

- `compose.yml`
- `Dockerfile`

As a reference, here are the `compose.yml` and `Dockerfile` for the Python container that is included by default. In `compose.yml`, add the name of the new container under `services`.

<details>
<summary>compose.yml</summary>

[compose.yml](https://raw.githubusercontent.com/yohasebe/monadic-chat/main/docker/services/python/compose.yml ':include :type=code')

</details>

In the `Dockerfile`, describe how to build the new container. Files to be copied in the Dockerfile should be placed in the same directory as `compose.yml` and `Dockerfile`.

<details>
<summary>Dockerfile</summary>

[Dockerfile](https://raw.githubusercontent.com/yohasebe/monadic-chat/main/docker/services/python/Dockerfile ':include :type=code dockerfile')

</details>

To add a container, you need to rebuild Monadic Chat. During this process, a `docker-compose.yml` file will be automatically generated in the `~/monadic/data` directory. This file is also used to remove images and containers, so please do not modify or delete it.

## Example of Adding a Container

To actually use a new container within the app, you need to either expose an API endpoint on that container so the app can access it, or add a new script to `~/monadic/data/scripts/` to include a command that uses the container. For an example of exposing an API endpoint on a container and accessing it from the app, see [Using the Ollama Container](/ja/ollama.md). For an example of adding a new script to the `scripts` folder, see below.

Here are the steps to add a Syntax Analysis app. The code can be downloaded from the [monadic-chat-extra](https://github.com/yohasebe/monadic-chat-extra) repository on GitHub.

```
~/monadic/data
├── apps
│   └── syntactic_analysis
│       ├── syntactic_analysis_app.rb
│       └── agents
│           ├── syntree_render_agent.rb
│           └── syntree_build_agent.rb
└── services
    └── rsyntaxtree
        ├── Dockerfile
        ├── compose.yml
        ├── Gemfile
        └── fonts/
```

Place the app scripts in the `apps` folder. The subfolder structure is arbitrary, and all Ruby scripts in the `apps` folder will be loaded. In the example above, a `syntactic_analysis` folder is created within the `apps` folder, and an `agents` folder is created within it, but the folder structure can be changed.

To be recognized as an app in Monadic Chat, you need to define a class that inherits from `MonadicApp` in those Ruby scripts (the class name `NewApp` is arbitrary). You also need to specify the vendor of the language model to be used. In the example below, the `OpenAIHelper` module is included.

```ruby
class NewApp < MonadicApp
  include OpenAIHelper
  @settings = {
    . . .
  }
end
```

To define functions that AI agents can use within an instance of a class that inherits from MonadicApp, write them in the MonadicAgent module. In the example above, this is done in `syntax_render_agent.rb` and `syntax_build_agent.rb`. Each file will have the following structure:

```ruby
module MonadicAgent
  def method1
    . . .
  end

  def method2
    . . .
  end
end
```

To make these defined functions recognizable to AI agents, explain their usage in the app's system prompt and add the function information in JSON format to the `tools` key in the `@settings` hash. The specific schema for function information varies by language model vendor, but generally follows the format below.

```JSON
{
  "name": "method1",
  "description": "This is a method1.",
  "args": [
    {
      "name": "arg1",
      "description": "This is an argument1.",
      "type": "string"
    },
    {
      "name": "arg2",
      "description": "This is an argument2.",
      "type": "string"
    }
  ]
}
```
