# Ollamaの利用

## セットアップ

Ollamaを利用するためには、以下のように必要なファイルを配置してMonadic Chatを再構築してください。

1. Ollama用追加ファイルをダウンロードします。

2. 共有フォルダの下記のサブフォルダにファイルを配置します。

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

3. Monadic Chatを再構築します。

4. Monadic Chatを起動します。Ollama (Chat)アプリが追加されていることを確認します。

## 言語モデルの追加

標準では、`llama3.1 (8B)`モデルが利用可能になっています。他の言語モデルを利用する場合は、ターミナルからOllamaコンテナーに接続して、追加したいモデルをダウンロードしてください。下記は`gemma2:2b`モデルを追加する例です。


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

`ollama`のインタラクティブシェルが起動して、モデルのダウンロードが完了すると、`>>>`プロンプトが表示されます。`/bye`と入力してシェルを終了します。

ターミナルからダウンロードしたモデルは、`Talk to Ollama`アプリを選択するとモデルのセレクターに選択肢として表示されます。
