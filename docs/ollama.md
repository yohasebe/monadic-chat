# Using Ollama

## Setup

To use Ollama, place the necessary files as shown below and rebuild Monadic Chat.

1. Download the additional files for Ollama.

2. Place the files in the following subfolders of the shared folder.

```
~
└── monadic
    └── data
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

3. Rebuild Monadic Chat.

4. Start Monadic Chat and confirm that the Ollama (Chat) app has been added.

## Adding Language Models

By default, the `llama3.1 (8B)` model is available. To use other language models, connect to the Ollama container from the terminal and download the model you want to add. Below is an example of adding the `gemma2:2b` model.

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

You can quit the interactive shell of `ollama` by typing `/bye`.
