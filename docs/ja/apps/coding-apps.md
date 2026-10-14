# コーディング・ノートブックアプリ

コードを書いて実行するためのアプリです。コンテナの中での Python の実行、コーディングの支援、Jupyter Notebook の作成ができます。

## Code Interpreter

![Code Interpreter app icon](../assets/icons/code-interpreter.png ':size=40')

AI に Python のコードを書かせ、Python コンテナで実行させるアプリです。コードが作ったテキストや画像は共有フォルダに保存され、チャットにも表示されます。AI は自分が作ったファイルを覚えているので、後のターンでそれらを参照できます。自分のファイル（スクリプトやデータ）を AI に渡すときは、共有フォルダに置き、メッセージの中でファイル名を伝えてください。

?> **注意：** Python コンテナには日本語のフォント（Noto Sans CJK JP）が入っていて、matplotlib はそれを使うように設定されているので、グラフの日本語は正しく表示されます。

Code Interpreter の対応プロバイダーは[モデル対応状況の表](../basic-usage/basic-apps.md#app-availability)を参照してください。


## Coding Assistant

![Coding Assistant app icon](../assets/icons/coding-assistant.png ':size=40')

ソフトウェア開発のためのアシスタントです。コードを書いて直し、共有フォルダのファイルを読み書きします。

**主な機能：**
- コードの生成と編集
- 共有フォルダのファイルの読み書き（上書きと追記）
- フォルダの中のファイルの一覧
- OpenAI 版と xAI（Grok）版では、大きなコーディングの作業を、同じプロバイダーのコード生成モデルに任せます

?> **注意：** Code Interpreter は Python のコードを実行します。Coding Assistant はコードを書き、ファイルを扱いますが、コードは実行しません。

Coding Assistant の対応プロバイダーは[モデル対応状況の表](../basic-usage/basic-apps.md#app-availability)を参照してください。


## Jupyter Notebook :id=jupyter-notebook

![Jupyter Notebook app icon](../assets/icons/jupyter-notebook.png ':size=40')

AI に Jupyter のノートブックを作らせ、頼んだとおりにセルを加えて実行させるアプリです。AI は今のノートブックを覚えているので、いくつものターンにわたって同じノートブックの編集と実行を続けられます。コードは Python コンテナで実行され、ノートブックは共有フォルダに保存されます。

?> JupyterLab の起動と停止は、AI に頼むほか、コンソールの **Actions** メニューの **Start JupyterLab** と **Stop JupyterLab** でもできます。[JupyterLab](../docker-integration/jupyterlab.md) を参照してください。
<br /><br /><!-- SCREENSHOT: Actionsメニュー - Start JupyterLabとStop JupyterLabのメニュー項目が表示されている様子 -->

Jupyter Notebook の対応プロバイダーは[モデル対応状況の表](../basic-usage/basic-apps.md#app-availability)を参照してください。
