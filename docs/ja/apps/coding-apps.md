# コーディング・ノートブックアプリ

コードの作成と実行のためのアプリです。サンドボックス化されたPython実行環境、プロフェッショナルなコーディング支援、Jupyter Notebookの作成に対応します。

## Code Interpreter

![Code Interpreter app icon](../assets/icons/code-interpreter.png ':size=40')

AIにプログラムコードを作成・実行させるアプリケーションです。プログラムの実行には、Dockerコンテナ内のPython環境が使用されます。実行結果として得られたテキストデータや画像は`Shared Folder`に保存されると共に、チャット上でも表示されます。

AIに読み込ませたいファイル（PythonコードやCSVデータなど）がある場合は、`Shared Folder` にファイルを保存して、Userメッセージの中でファイル名を指定してください。AIがファイルの場所を見つけられない場合は、ファイル名を確認して、現在のコード実行環境から利用可能であることを伝えてください。

?> **注意:** 日本語テキストを含むmatplotlibプロットでは、Pythonコンテナに日本語フォントサポート（Noto Sans CJK JP）がmatplotlibrcを通じて設定されています。

コードがプロット画像を生成した場合、AIは描画結果を視覚的に検証し、文字化け、ラベルの重なり、データの不整合などの問題を検出して、必要に応じてコードを自動修正・再実行します。

Code Interpreterの対応プロバイダーは[モデル対応状況の表](../basic-usage/basic-apps.md#app-availability)を参照してください。


## Coding Assistant

![Coding Assistant app icon](../assets/icons/coding-assistant.png ':size=40')

プロフェッショナルなソフトウェアエンジニアとして機能するAIアシスタントです。コードの作成、ファイルの読み書き、プロジェクト管理など、開発作業全般をサポートします。

**主な機能:**
- コードの生成と編集
- Shared Folderへのファイル読み書き（write/appendモード対応）
- ディレクトリ内のファイルリスト表示
- 複雑なコーディングタスクへの対応

?> **注意:** Code InterpreterアプリはPythonコードを実行できますが、Coding Assistantアプリはコード生成とファイル操作に特化しており、コードの実行は行いません。


Coding Assistantの対応プロバイダーは[モデル対応状況の表](../basic-usage/basic-apps.md#app-availability)を参照してください。


## Jupyter Notebook :id=jupyter-notebook

![Jupyter Notebook app icon](../assets/icons/jupyter-notebook.png ':size=40')

AIがJupyter Notebookを作成して、ユーザーからのリクエストに応じてセルを追加し、セル内のコードを実行するアプリケーションです。コードの実行には、Dockerコンテナ内のPython環境が使用されます。作成されたNotebookは`Shared Folder`に保存されます。セルがプロット画像を生成した場合、AIは出力結果を視覚的に検証し、問題があれば修正してから結果を提示します。

?> Jupyterノートブックを実行するためのJupyterLabサーバーの起動と停止は、AIエージェントに自然言語で依頼する他に、Monadic Chatコンソールパネルのメニューからも行うことができます（`Start JupyterLab`, `Stop JupyterLab`）。
<br /><br /><!-- SCREENSHOT: Actionsメニュー - Start JupyterLabとStop JupyterLabのメニュー項目が表示されている様子 -->

?> **注意:** サーバーモードでの制約については、[JupyterLab - Server モードでの制限](../docker-integration/jupyterlab.md#server-mode-restrictions)を参照してください。

Jupyter Notebookの対応プロバイダーは[モデル対応状況の表](../basic-usage/basic-apps.md#app-availability)を参照してください。
