# Using Ollama

## Setup

To use Ollama with Monadic Chat, you need to download additional files and rebuild Monadic Chat.  Follow these steps:

1. Download the necessary Ollama files from the [Monadic Chat Extra](https://github.com/yohasebe/monadic-chat-extra) repository.  You'll need the `ollama` folder containing the `apps`, `services`, and `helpers` subfolders.

2. Place the downloaded `ollama` folder into the `plugins` directory within your Monadic Chat shared folder.  The resulting file structure should look like this:

```
~
└── monadic
    └── data
        └── plugins
            └── ollama
                ├── apps
                │   └── talk_to_ollama
                │       └── talk_to_ollama_app.rb
                ├── services
                │   └── ollama
                │       ├── compose.yml
                │       ├── Dockerfile
                │       └── entrypoint.sh
                └── helpers
                    └── ollama_helper.rb
```

3. Rebuild Monadic Chat to incorporate the Ollama plugin.  You can do this through the Monadic Chat console.

4. Start Monadic Chat. You should now see the "Ollama (Chat)" app added to the list of available apps.

## Adding Language Models

By default, the `llama2.3 (3B)` model is available. To add other language models, connect to the Ollama container from your terminal and download the desired model using the `ollama run` command. For example, to add the `gemma2:2b` model:

```shell
$ docker exec -it monadic-chat-ollama-container bash
$ ollama run gemma2:2b
pulling manifest
pulling 7462734796d6... 100% ▕████████████▏ 1.6 GB
pulling e0a42594d802... 100% ▕████████████▏  358 B
pulling 097a36493f71... 100% ▕████████████▏ 8.4 KB
pulling 2490e7468436... 100% ▕████████████▏   65 B
pulling e18ad7af7efb... 100% ▕████████████▏  487 B
verifying sha256 digest
writing manifest
success
>>>
```

After the model finishes downloading, you'll see an interactive Ollama shell prompt (`>>>`). Type `/bye` to exit the shell.

The models you've added will be available for selection in the "Talk to Ollama" app.

!> Loading locally downloaded models into the Docker container can take some time. Reload the web interface if the model doesn't appear immediately, especially after adding a new model or restarting Monadic Chat.
