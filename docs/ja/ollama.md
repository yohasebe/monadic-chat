# Ollamaの利用

## セットアップ

Ollamaを利用するためには[Monadic Chat Extra](https://github.com/yohasebe/monadic-chat-extra)から追加ファイルをダウンロードする必要があります。ダウンロードしたファイルを共有フォルダに配置することでOllamaを利用することができます。

以下のように必要なファイルを配置してMonadic Chatを再構築（rebuild）してください。

1. Ollama用追加ファイルをダウンロードします。

2. 共有フォルダの`plugins`フォルダ内にファイルを配置します。

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

3. Monadic Chatを再構築します。

4. Monadic Chatを起動します。Ollama (Chat)アプリが追加されていることを確認します。

## 言語モデルの追加

標準では、`llama3.2 (3B)`モデルが利用可能になっています。他の言語モデルを利用する場合は、ターミナルからOllamaコンテナーに接続して、追加したいモデルをダウンロードしてください。下記は`gemma2:2b`モデルを追加する例です。


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

!> ローカルでダウンロードしたモデルは、ロードに時間がかかる場合があります。コンテナを再構築した後や、Monadic Chatを再起動した後、webインターフェイスにモデルが表示されるまでに時間がかかることがあります。そのような時は少し時間を空けてからwebインターフェイスをリロードしてください。

