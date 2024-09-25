# アプリの開発

Monadic Chatでは、オリジナルのシステムプロンプトを用いたAIチャットボット・アプリケーションを開発することができます。このページでは、新しいアプリケーションを開発するための手順を説明します。

## シンプルなアプリの追加方法

1. アプリのレシピ・ファイルを作成します。レシピファイルはRubyのプログラムで記述されます。
2. レシピ・ファイルを共有フォルダの`apps`ディレクトリに保存します（`~/monadic/data/apps`）。
3. Monadic Chatを再起動します。

レシピ・ファイルは`~/monadic/data/apps`ディレクトリ以下の任意のディレクトリに保存することができます。

### 高度なアプリの追加方法

アプリのレシピファイルは`MonadicApp`を継承したクラスを定義し、インスタンス変数`@settings`にアプリケーションの設定を記述します。ヘルパーフォルダにモジュールを定義すれば、複数のアプリで使うことができる共通の機能を実装できます。

また、標準コンテナ以外の新たなコンテナを追加する場合は、`services`フォルダにDocker関連ファイルを格納します。
コンテナ内で利用可能な特定のコマンドを実行したい時や、コードを実行したい場合は、すべての追加アプリの基底クラスである`MonadicApp`に定義されている`send_command`メソッドまたは`send_code`メソッドを使用します。

これらを組み合わせてアプリを定義する場合、次のようなフォルダ構成になります。

```text
~/
└── monadic
    └── data
        ├── apps
        │   └── my_app
        │       └── my_app.rb
        ├── helpers
        │   └── my_helper.rb
        └── services
            └── my_service
                ├── compose.yml
                └── Dockerfile

```

## プラグインの作成

共有フォルダ直下の`apps`、`helpers`、`services`にファイルを追加していくと、コードの管理が難しくなったり、再配布することが難しくなる可能性があります。追加アプリを単一のフォルダ内にまとめ、プラグインとして開発することができます。

プラグインを作成するには、`~/monadic/data/plugins`以下にその場合、プラグインフォルダの直下に`apps`やその他のフォルダを作成し、必要なファイルを格納します。

```text
~/
└── monadic
    └── data
        └── plugins
            └── my_plugin
                ├── apps
                │   └── my_app
                │       └── my_app.rb
                ├── helpers
                │   └── my_helper.rb
                └── services
                    └── my_service
                        ├── compose.yml
                        └── Dockerfile
```

上記ではメインのレシピ・ファイルのほかにヘルパーファイルを用いており、追加のコンテナを作成するためのDocker関連ファイルを格納するサービスフォルダも含まれています。シンプルなアプリの場合、レシピ・ファイルのみを保存しても問題ありません。

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

## アプリ内での関数呼び出し

アプリ内でAIエージェントが使用できる関数を定義することが可能です。Rubyで関数を定義して、``@settings`の`tools`に関数名や引数などを指定し、`initial_prompt`に関数の使用方法を記述します。

各コンテナで利用可能な特定のコマンドを実行したい時や、Pythonの関数を使用したい場合は、すべての追加アプリの基底クラスである`MonadicApp`に定義されている`send_command`メソッドまたは`send_code`メソッドを使用してください。

### `send_command`

`send_command`メソッドは、コンテナ内でパスが通っているコマンドを実行するためのメソッドです。引数にはコマンドを文字列で指定します。戻り値はコマンドの実行結果の文字列です。

```ruby
send_command(command: "ls", container: "python", success: "Command executed successfully."")
```

例として、上記のコードはPythonコンテナ内で`ls`コマンドを実行し、その結果を返します。`command`引数は実行するコマンドを指定します。`container`引数はコマンドを実行するコンテナを略記で指定します。`python`と指定した場合は`monadic-chat-python-container`を指定することになります。`success`引数はコマンドの実行が成功した場合に、コマンドの実行結果の文字列の前に挿入するメッセージを指定します。

### `send_code`

`send_code`メソッドは、コンテナ内でプログラムのコードを実行するためのメソッドです。与えられたコードを一時ファイルに保存し、指定されたプログラムでそのファイルを実行します。`code`引数にはコードを文字列で指定します。`command`引数には、コードを実行するプログラムを指定します。`extension`引数には、一時ファイルの拡張子を指定します。コードの実行が成功したとき、結果として新しいファイルが生成されたかどうかによって、結果として返される文字列が異なります。

```ruby
send_code(code: "print('Hello, World!')", command: "python", extension: "py")
```

例として、上記のコードはPythonコンテナ内で`print('Hello, World!')`コードを実行し、その結果を返します。`code`引数は実行するコードを指定します。`command`引数はコードを実行するプログラムを指定します。`extension`引数は一時ファイルの拡張子を指定します。

`send_code`メソッドは、コード実行後に新しいファイルが生成されたかどうかを検知し、その結果によって返される文字列が異なります。

**ファイルが生成されていない場合**

```text
The code has been executed successfully; Output: OUTPUT
```

**ファイルが生成されている場合**

```text
The code has been executed successfully; Files generated: NEW FILE; Output: OUTPUT
```

アプリ内で使用するメソッドから`send_command`または`send_code`メソッドを呼び出して、その結果に応じてAIエージェントにメッセージを返すことにより、Dockerコンテナの機能を生かした高度な機能を実現することができます。
