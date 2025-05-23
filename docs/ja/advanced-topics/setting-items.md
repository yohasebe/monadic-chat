# アプリの設定項目

各アプリの設定項目は`MonadicApp`を継承したクラスの`@settings`インスタンス変数に記述します。
設定項目には必須のものと任意の物があります。必須の設定項目が指定されていない場合は、アプリケーションの起動時にブラウザ画面上にエラーメッセージが表示されます。

## 必須の設定項目

`display_name` (string, 必須)

ユーザーインターフェースに表示されるアプリケーションの名前（必須）を指定します。

`icon` (string, 必須)

アプリケーションのアイコン（絵文字またはHTML）を指定します。

`description` (string, 必須)

アプリケーションの説明を記述します。

`initial_prompt` (string, 必須)

システムプロンプトのテキストを指定します。

## 任意の設定項目

`group` (string)

Web 設定画面の Base App セレクタ上でアプリをグループ化するためのグループ名を指定します。独自のアプリを追加する場合には、基本アプリと区別するために何らかのグループ名を指定することが推奨されます。

![](../assets/images/groups.png ':size=300')

`model` (string)

デフォルトのモデルを指定します。指定されていない場合は（`OpenAIHelper`モジュールをインクルードしているアプリの場合）`gpt-4o`が使用されます。

`temperature` (float)

デフォルトの温度を指定します。

`presence_penalty` (float)

デフォルトの`presence_penalty`を指定します。OpenAI と Mistral AI のモデルで利用可能です。モデルが対応していない場合は無視されます。

`frequency_penalty` (float)

デフォルトの`frequency_penalty`を指定します。OpenAI と Mistral AI のモデルで利用可能です。モデルが対応していない場合は無視されます。

`max_tokens` (int)

デフォルトの`max_tokens`を指定します。`max_output_tokens`としても利用可能です。

`context_size` (int)

デフォルトの`context_size`を指定します。

`easy_submit` (bool)

テキストボックスに入力したメッセージをENTERキーだけで送信するかどうかを指定します。

`auto_speech` (bool)

AIアシスタントの応答を音声で読み上げるかどうかを指定します。

`image` (bool)

AIアシスタントに送信するメッセージボックスに画像添付のボタンを表示するかどうかを指定します。

`pdf` (bool)

PDFデータベース機能を有効にするかどうかを指定します。

`initiate_from_assistant` (bool)

ユーザーより先にAIアシスタントからの最初のメッセージで始めるかどうかを指定します。

`sourcecode` (bool)

プログラム・コードのシンタックスハイライトを有効にするかどうかを指定します。`code_highlight`としても利用可能です。

`mathjax` (bool)

[MathJax](https://www.mathjax.org/)を用いた数式のレンダリングを有効にするかどうかを指定します。

`jupyter` (bool)

会話内でJupyter notebooksへのアクセスを有効にする場合に`true`を指定します。`jupyter_access`としても利用可能です。

`monadic` (bool)

アプリをMonadicモードに指定します。Monadicモードについては[Monadicモード](./monadic-mode.md)を参照してください。

`prompt_suffix` (string)

ユーザーからのメッセージの末尾に毎回追加する文字列を指定します。システムプロンプトで指示した内容のうち、AIエージェントに必ず守ってほしい重要な内容を明示的に伝えて、無視されないようリマインドするために使用します。

`file` (bool)

アプリのウェブ設定画面でテキストファイルのアップロード機能を有効にするかどうかを指定します。アップロードされたファイルの内容はシステム・プロンプトの末尾に追加されます。

`websearch` (bool)

外部情報の取得のためにウェブ検索機能を有効にするかどうかを指定します。これにより、AIアシスタントは最新の情報をウェブから検索することができます。`web_search`としても利用可能です。

`image_generation` (bool)

会話内でAI画像生成機能を有効にするかどうかを指定します。有効にすると、AIはテキスト説明に基づいて画像を生成できるようになります。

`mermaid` (bool)

Mermaidダイアグラムのレンダリングと対話機能を有効にするかどうかを指定します。これにより、フローチャート、シーケンス図、その他の視覚的な表現を会話内で直接作成および表示することができます。

`reasoning_effort` (string)

モデルの推論の深さを指定します（例：「high」）。このパラメータは、モデルが複雑な問題をどの程度徹底的に推論するかを制御するために使用されます。

`abc` (bool)

AIエージェントのレスポンスに[ABC記譜法](https://abcnotation.com/)で入力された楽譜の表示・再生機能を有効にするかどうかを指定します。ABC記譜法は音楽の楽譜を記述するための形式です。

`disabled` (bool)

アプリを無効にするかどうかを指定します。無効にしたアプリはMonadic Chatのメニューに表示されません。

`toggle` (bool)

AIエージェントのレスポンスの一部（メタ情報、ツール使用）をトグル表示するかどうかを指定します。現在は`ClaudeHelper`モジュールをインクルードしているアプリのみで使用可能です。

`models` (array)

使用可能なモデルのリストを指定します。指定がない場合はインクルードしているモジュール（`OpenAIHelper`など）で用意しているモデルのリストが使用されます。

`tools` (array)

使用可能な関数のリストを指定します。ここで指定した関数の実際の定義はレシピ・ファイル内に記述するか、もしくは別のファイルの中で、`MonadicApp`クラスのインスタンスメソッドとして記述します。

`response_format` (hash)

JSON形式で出力する場合の出力形式を指定します。詳細については[OpenAI: Structured outputs](https://platform.openai.com/docs/guides/structured-outputs)を参照してください。

## システムレベルの設定

以下の設定項目はシステムレベルで管理され、レシピファイルで直接設定することはできません。これらはMonadic Chatの設定UI画面で設定されます。

`STT_MODEL` (string)

アプリケーション全体で使用される音声認識（Speech-to-Text）モデルを指定します。利用可能なオプションにはwhisper-1、gpt-4o-mini-transcribe、gpt-4o-transcribeがあります。選択したモデルに基づいて音声フォーマットが自動的に最適化されます。

`AI_USER_MODEL` (string)

AI生成によるユーザーメッセージに使用されるモデルを指定します。利用可能なオプションにはgpt-4.1, gpt-4.1-mini, gpt-4.1-nano, gpt-4o-mini、gpt-4o、o3-mini、o1-mini、o1があります。

`EMBEDDING_MODEL` (string)

テキスト埋め込み生成に使用されるモデルを指定します。利用可能なオプションにはtext-embedding-3-small、text-embedding-3-largeがあります。

`WEBSEARCH_MODEL` (string)

ウェブ検索機能に使用されるモデルを指定します。利用可能なオプションにはgpt-4o-mini-search-preview、gpt-4o-search-previewがあります。

`ROUGE_THEME` (string)

アプリケーション全体で使用されるシンタックスハイライトのテーマを指定します。

