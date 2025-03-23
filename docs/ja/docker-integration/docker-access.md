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

