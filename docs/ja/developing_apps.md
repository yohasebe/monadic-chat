# アプリの開発

Monadic Chatでは、オリジナルのシステムプロンプトを用いたAIチャットボット・アプリケーションを開発することができます。このページでは、新しいアプリケーションを開発するための手順を説明します。

## 追加方法

1. アプリのレシピ・ファイルを作成します。レシピファイルはRubyのプログラムで記述されます。
2. レシピ・ファイルを共有フォルダの`apps`ディレクトリに保存します（`~/monadic/data/apps`）。
3. Monadic Chatを再起動します。

レシピ・ファイルは正しく記述されていれば`apps`ディレクトリ以下の任意のディレクトリに保存することができます。ただし、慣例的には`apps`ディレクトリ直下に`app_name`ディレクトリを作成し、その中に`app_name_app.rb`と名付けたレシピ・ファイルを保存することが推奨されます。

## レシピ・ファイルの記述

レシピ・ファイルには`MonadicApp`を継承したクラスを定義し、インスタンス変数`@settings`にアプリケーションの設定を記述します。

```ruby
class RobotApp < MonadicApp
  include OpenAIHelper
  @settings = {
    app_name: "Robot App",
    icon: "🤖",
    description: "This is a sample robot app.",
    initial_prompt: "You are a friendly robot that can help with anything the user needs. You talk like a robot, always ending your sentences with '...beep boop'.",
  }
end
```

Rubyスクリプトとして有効ではなく、エラーが発生する場合、Monadic Chatが起動せず、エラーメッセージが表示されます。具体的なエラーの詳細は共有フォルダ内に保存されるログファイルに記録されます（`~/monadic/data/error.log`）。

## 設定項目

設定項目には必須のものと任意の物があります。必須の設定項目が指定されていない場合、アプリケーションの起動時にブラウザ画面上にエラーメッセージが表示されます。

`app_name` (string, 必須)

アプリケーションの名前（必須）を指定します。

`icon` (string, 必須)

アプリケーションのアイコン（絵文字またはHTML）を指定します。

`description` (string, 必須)

アプリケーションの説明を記述します。

`initial_prompt` (string, 必須)

システムプロンプトのテキストを指定します。

`model` (string)

デフォルトのモデルを指定します。指定されていない場合は（`OpenAIHelper`モジュールをインクルードしているアプリの場合）`gpt-4o-mini`が使用されます。

`temperature` (float)

デフォルトの温度を指定します。


`presence_penalty` (float)

デフォルトの`presence_penalty`を指定します。モデルが対応していない場合は無視されます。

`frequency_penalty` (float)

デフォルトの`frequency_penalty`を指定します。モデルが対応していない場合は無視されます。

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

アプリをMonadicモードに指定します。Monadicモードについては[Monadicモード](/ja/monadic-mode)を参照してください。

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
