# アプリの設定項目

各アプリの設定項目は`MonadicApp`を継承したクラスの`@settings`インスタンス変数に記述します。
設定項目には必須のものと任意の物があります。必須の設定項目が指定されていない場合は、アプリケーションの起動時にブラウザ画面上にエラーメッセージが表示されます。

## 必須の設定項目

`app_name` (string, 必須)

アプリケーションの名前（必須）を指定します。

`icon` (string, 必須)

アプリケーションのアイコン（絵文字またはHTML）を指定します。

`description` (string, 必須)

アプリケーションの説明を記述します。

`initial_prompt` (string, 必須)

システムプロンプトのテキストを指定します。

## 任意の設定項目

`group` (string)

Web 設定画面の Base App セレクタ上でアプリをグループ化するためのグループ名を指定します。独自のアプリを追加する場合には、基本アプリと区別するために何らかのグループ名を指定することが推奨されます。

![](./assets/images/groups.png ':size=300')

`model` (string)

デフォルトのモデルを指定します。指定されていない場合は（`OpenAIHelper`モジュールをインクルードしているアプリの場合）`gpt-4o-mini`が使用されます。

`temperature` (float)

デフォルトの温度を指定します。

`presence_penalty` (float)

デフォルトの`presence_penalty`を指定します。OpenAI と Mistral AI のモデルで利用可能です。モデルが対応していない場合は無視されます。

`frequency_penalty` (float)

デフォルトの`frequency_penalty`を指定します。OpenAI と Mistral AI のモデルで利用可能です。モデルが対応していない場合は無視されます。

`top_p` (float)

デフォルトの`top_p`を指定します。モデルが対応していない場合は無視されます。

`max_tokens` (int)

デフォルトの`max_tokens`を指定します。

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

プログラム・コードのシンタックスハイライトを有効にするかどうかを指定します。

`mathjax` (bool)

[MathJax](https://www.mathjax.org/)を用いた数式のレンダリングを有効にするかどうかを指定します。

`jupyter` (bool)

Jupyter Notebookと連携する場合に`true`を指定します（MathJaxの表示を最適化します）。

`monadic` (bool)

アプリをMonadicモードに指定します。Monadicモードについては[Monadicモード](./monadic-mode)を参照してください。

`prompt_suffix` (string)

ユーザーからのメッセージの末尾に毎回追加する文字列を指定します。システムプロンプトで指示した内容のうち、AIエージェントに必ず守ってほしい重要な内容を明示的に伝えて、無視されないようリマインドするために使用します。

`file` (bool)

アプリのウェブ設定画面でテキストファイルのアップロード機能を有効にするかどうかを指定します。アップロードされたファイルの内容はシステム・プロンプトの末尾に追加されます。

`abc` (bool)

AIエージェントのレスポンスに[ABC記譜法](https://abcnotation.com/)で入力された楽譜の表示・再生機能を有効にするかどうかを指定します。ABC記譜法は音楽の楽譜を記述するための形式です。

`disabled` (bool)

アプリを無効にするかどうかを指定します。無効にしたアプリはMonadic Chatのメニューに表示されません。

`toggle` (bool)

AIエージェントのレスポンスの一部（メタ情報、ツール使用）をトグル表示するかどうかを指定します。現在は`ClaudeHelper`モジュールをインクルードしているアプリのみで使用可能です。

`models` (array)

使用可能なモデルのリストを指定します。指定がない場合はインクルードしているモジュール（`OpenAIHelper`など）で用意しているモデルのリストが使用されます。

`tools` (array)

使用可能な関数のリストを指定します。ここで指定した関数の実際の定義はレシピ・ファイル内に記述するか、もしくは別のファイルの中で、`MonadicAgent`モジュールのインスタンスメソッドとして記述します。

`response_format` (hash)

JSON形式で出力する場合の出力形式を指定します。詳細については[OpenAI: Structured outputs](https://platform.openai.com/docs/guides/structured-outputs)を参照してください。

