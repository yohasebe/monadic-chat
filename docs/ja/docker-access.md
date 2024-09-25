# Dockerコンテナ

## 標準コンテナ

標準では下記のコンテナが構築されます。

**Rubyコンテナ**（`monadic-chat-ruby-container`）

Monadic Chatのアプリケーションを実行するためのコンテナです。Webインターフェイスを提供するためにも使用されます。

**Pythonコンテナ**（`monadic-chat-python-container`）

Monadic Chatの機能を拡張するためのPythonスクリプトを実行するために使用されます。JupyterLabもこのコンテナ上で実行されます。

**Seleniumコンテナ**（`monadic-chat-selenium-container`）

Seleniumを使用して仮想的なWebブラウザを操作して、Webページのスクレイピングを行うために使用されます。

**pgvectorコンテナ**（`monadic-chat-pgvector-container`）

Postgresql上にテキスト埋め込みのベクトルデータを保存するため、pgvectorを使用するためのコンテナです。


?> 追加のDockerコンテナを導入する方法については、[Dockerコンテナの追加](/ja/adding-containers.md)を参照してください。

# Dockerコンテナへのアクセス

Dockerコンテナにアクセスする方法は2つあります。

## Dockerコマンド

Dockerコンテナにアクセスするためには、`docker exec`コマンドを使用します。例えば、`monadic-chat-python-container`にアクセスするには、ターミナル上で以下のコマンドを実行します。

```shell
docker exec -it monadic-chat-python-container bash
```

Monadic ChatコンソールでStartをクリックすると、すべてのコンテナが起動します。起動が完了すると、コンテナにアクセスするためのコマンドが表示されるので、それをコピーしてターミナルに貼り付けて実行します。

![Start JupyterLab](../assets/images/docker-commands.png ':size=600')

## JupyterLab

Monadic Chatコンソールの`Actions/Start JupyterLab`メニューを使用してJupyterLabを起動すると、Pythonコンテナ上の`/monadic/data`をカレントディレクトリとしてJupyterLabが起動します。JupyterLabのLauncher画面で`Terminal`をクリックすると、Pythonコンテナにアクセスできます。

![JupyterLab Terminal](../assets/images/jupyterlab-terminal.png ':size=600')

