# JupyterLabとの連携

Monadic Chatには、JupyterLabを起動する機能があります。JupyterLabは、データサイエンスや機械学習のための統合開発環境（IDE）です。JupyterLabを使用することで、Pythonを用いてデータの分析や可視化を行うことができます。

## JupyterLabの起動

Monadic Chatコンソールの`Actions/Start JupyterLab`メニューをクリックすると、JupyterLabが起動します。

- JupyterLabは`http://localhost:8889`または`http://127.0.0.1:8889`でアクセスできます
- パスワードやトークンは不要です（ローカル使用専用に設定）

![Action menu](../assets/images/jupyter-start-stop.png ':size=190')

JupyterLabを起動すると、`/monadic/data`をホームディレクトリとしてJupyterLabが起動します。このため、JupyterLab内でも共有フォルダ内のファイルにアクセスできます。

![JupyterLab Terminal](../assets/images/jupyterlab-terminal.png ':size=600')

## JupyterLabの停止

JupyterLabを停止するには、JupyterLabのタブを閉じるか、Monadic Chatコンソールの`Actions/Stop JupyterLab`メニューをクリックします。

## JupyterLabアプリの利用

Monadic Chatの基本アプリ`Jupyter Notebook`では、AIエージェントとのチャットを通じて次のようなことができます。

- JupyterLabの起動と停止
- 共有フォルダへの新規ノートブックの作成
- 共有フォルダ内のノートブックの読み込み
- ノートブックへの新規セルの追加

## 異なるモードでのJupyterアクセス

### Standalone モード

Standalone モードでは、すべてのJupyter機能が完全に利用可能です：
- JupyterLabインターフェースは`http://127.0.0.1:8889`でアクセス可能
- アプリケーションメニューに`Jupyter Notebook`アプリが表示される
- AIエージェントがJupyterノートブックの作成、変更、実行を行える

### Server モードでの制限

Monadic ChatをServer モードで実行する場合、セキュリティ上の理由からJupyter機能はデフォルトで無効化されています：

- **Jupyterアプリはアプリケーションメニューから非表示**になります
- Server モードでJupyterを有効にするには、設定変数を設定: `~/monadic/config/env`に`ALLOW_JUPYTER_IN_SERVER_MODE=true`
- Server モードでは複数のデバイスからのネットワークアクセスが可能
- JupyterLabは共有フォルダと結びついており、信頼できないユーザーがアクセスするとセキュリティリスクとなる
- Server モードは信頼された環境でのみ使用することを強く推奨
- **警告**: Server モードでJupyterを有効にすると、共有フォルダへの完全なアクセス権限で任意のコード実行が許可されます

Server モードでJupyterアプリを有効にする方法、`~/monadic/config/env`ファイルに以下を追加：
```
ALLOW_JUPYTER_IN_SERVER_MODE=true
```

これらの制限は、Jupyterが任意のコード実行を許可するため、マルチユーザー環境では危険となる可能性があるためです。

## JupyterLab使用のヒント

- **作業ディレクトリ**: JupyterLabは`/monadic/data`を作業ディレクトリとして起動します
- **永続的ストレージ**: `/monadic/data`に保存されたすべてのファイルはコンテナの再起動後も保持されます
- **Pythonパッケージ**: ノートブックのセルで`pip install`を使用して追加パッケージをインストールできます
- **ターミナルアクセス**: JupyterLabのTerminalを使用してPythonコンテナに直接アクセスできます

## 関連アプリ

- **Code Interpreter**: JupyterLabを開かずにチャット内でPythonコードを直接実行
- **Jupyter Notebook**: チャットを通じてJupyterノートブックを作成・管理するAIエージェント
- 両アプリはJupyterLabと同じPython環境を使用します

