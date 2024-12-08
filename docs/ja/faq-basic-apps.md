# FAQ: 基本アプリ

**Q**: プログラミングなしで、簡単に基本アプリを拡張する方法はありますか？

**A**: はい、適当な基本アプリを選択した後、Web UI上でシステムプロンプトなどの設定を自由に変更することができます。また、変更した状態でセッションをエクスポートすることで、必要な時に同じ状態を呼び出すことができます。

![](./assets/images/monadic-chat-session.png ':size=400')

**Q**: `Code Interpreter`アプリと`Coding Assistant`と`Jupyter Notebook`アプリの違いは何ですか？

**A**: `Code Interpreter`アプリは、Pythonコンテナ上のPython処理系を利用してPythonスクリプトを実行するアプリです。AIエージェントにPythonコードを書いてもらうだけでなく、実際に実行して結果を得ることができます。また、Pythonスクリプト以外にも、CSVファイル、Microsoft Officeファイル、オーディオファイル（MP3, WAV）を読み込んで処理することができます。

`Coding Assistant`アプリは、様々なプログラム（Python, Ruby, JavaScript, etc.）の作成を支援するための機能を提供します。AIエージェントにコードを実行させることはできませんが、ソースコードを提供して、問題点の修正を依頼したり、機能の追加を依頼したりすることができます。

トークン数には制限がありますが、ソースコードをキャッシュして、次々と修正を依頼することが可能です。`Coding Assistant`アプリでは、`prompt caching`（AnthropicとOpenAIモデル）と`predicted outputs`（Open AIモデル）の機能を利用して、効率的に修正を依頼する方法を提供しています

`Jupyter Notebook`アプリは、JupyterLabを利用して、Jupyter Notebookのセルを記述・実行するアプリです。AIエージェントにセルに入力すべきコードを考えてもらうだけでなく、共有フォルダ内にノートブック（`ipynb`ファイル）を作成して、次々とセルを追加・実行させることができます。ライブラリのチュートリアルを作成したり、プログラミング教育用のノートブックを作成したりする際の支援ツールとして利用できます。
