# コンテナへのアクセス

Dockerコンテナにアクセスする方法について説明します。Dockerコンテナ上で新たなフソフトウェアをインストールしたり、ファイルを編集したりして、Monadic Chatの機能を拡張することができます。

Dockerコンテナにアクセスする方法は2つあります。

## Dockerコマンド

Dockerコンテナにアクセスするためには、`docker exec`コマンドを使用します。例えば、`monadic-chat-python-container`にアクセスするには、ターミナル上で以下のコマンドを実行します。

```shell
docker exec -it monadic-chat-python-container bash
```

Monadic ChatコンソールでStartをクリックすると、すべてのコンテナが起動します。起動が完了すると、コンテナにアクセスするためのコマンドが表示されるので、それをコピーしてターミナルに貼り付けて実行します。

## JupyterLab

Monadic Chatコンソールの`Actions/Start JupyterLab`メニューを使用してJupyterLabを起動すると、Pythonコンテナ上の`/monadic/data`をカレントディレクトリとしてJupyterLabが起動します。JupyterLabのLauncher画面で`Terminal`をクリックすると、Pythonコンテナにアクセスできます。
