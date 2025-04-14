# JupyterLabとの連携

Monadic Chatには、JupyterLabを起動する機能があります。JupyterLabは、データサイエンスや機械学習のための統合開発環境（IDE）です。JupyterLabを使用することで、Pythonを用いてデータの分析や可視化を行うことができます。

## JupyterLabの起動

Monadic Chatコンソールの`Actions/Start JupyterLab`メニューをクリックすると、JupyterLabが起動します。

- Standalone モードの場合: JupyterLabは`http://localhost:8889`または`http://127.0.0.1:8889`でアクセスできます

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

Monadic ChatをServer モードで実行する場合、セキュリティ上の理由からJupyter機能は制限されます：

- アプリケーションメニューから`Jupyter Notebook`アプリが自動的に非表示になる
- Jupyter機能に依存する関連アプリも非表示になる
- Actionsメニューを通じたJupyterLabへの直接アクセスは技術的には可能
- Server モードは信頼された環境でのみ使用することを推奨

これらの制限は、Jupyterが任意のコード実行を許可するため、ネットワークに公開するとセキュリティリスクとなる可能性があるため実装されています。

マルチユーザー環境でJupyter機能が必要な場合は、以下を推奨します：
1. 個々のマシンでStandalone モードでMonadic Chatを実行する
2. Jupyterを必要としない協調機能のみにServer モードを使用する

