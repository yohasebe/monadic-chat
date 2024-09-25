# アプリの開発

Monadic Chatでは、オリジナルのシステムプロンプトを用いたAIチャットボット・アプリケーションを開発することができます。このセクションでは、新しいアプリケーションを開発するための手順を説明します。

## シンプルなアプリの追加方法

1. アプリのレシピ・ファイルを作成します。レシピファイルはRubyのプログラムで記述されます。
2. レシピ・ファイルを共有フォルダの`apps`ディレクトリに保存します（`~/monadic/data/apps`）。
3. Monadic Chatを再起動します。

レシピ・ファイルは`~/monadic/data/apps`ディレクトリ以下の任意のディレクトリに保存することができます。

レシピ・ファイルの作成方法については、[レシピ・ファイルの記述](#レシピ・ファイルの記述)を参照してください。

## 高度なアプリの追加方法

アプリのレシピファイルは`MonadicApp`を継承したクラスを定義し、インスタンス変数`@settings`にアプリケーションの設定を記述します。`helpers`フォルダ内のRubyファイルはレシピファイルよりも先に読み込まれるため、アプリケーションの機能を拡張するためにヘルパーファイルを使用することができます。例えば、ヘルパーフォルダにモジュールを定義して、レシピファイルで定義する`MonadicApp`を継承したクラスに`include`するということが可能です。このようにすれば、共通の機能をモジュールとしてまとめておき、複数のアプリで再利用することができます。

また、標準コンテナ以外の新たなコンテナを追加したい場合は、`services`フォルダにDocker関連ファイルを格納します。
コンテナ内で利用可能な特定のコマンドを実行したい時や、コードを実行したい場合は、すべての追加アプリの基底クラスである`MonadicApp`に定義されている`send_command`メソッドまたは`send_code`メソッドを使用します（詳細については[関数・ツールの呼び出し](#関数・ツールの呼び出し)を参照してください）。

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

共有フォルダ直下の`apps`、`helpers`、`services`にファイルを次々と追加していくと、コードの管理が難しくなったり、再配布することが難しくなる可能性があります。追加アプリを単一のフォルダ内にまとめて、パッケージ化されたプラグインとして開発することができます。

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

レシピ・ファイルでは次のことを行います。

1. `MonadicApp`を継承したクラスを定義する。
2. 言語モデルと連携するためのモジュール（`OpenAIHelper`など）をインクルードする。
3. インスタンス変数`@settings`にアプリケーションの設定を記述する。

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

言語モデルと連携するためのモジュールとして、下記が利用可能です。

- `OpenAIHelper`
- `ClaudeHelper`
- `CommandRHelper`
- `MistralHelper`
- `GeminiHelper`

?> `OpenAIHelper`、`ClaudeHelper`、`CommandRHelper`, `MistralHelper`では "function calling" や "tool use" の機能を使うことができます（[関数・ツールの呼び出し](#関数・ツールの呼び出し)を参照）。)を参照）。現在、`GeminiHelper`ではこれらの機能を利用できません。

!> レシピファイルがRubyスクリプトとして有効ではなく、エラーが発生する場合、Monadic Chatが起動せず、エラーメッセージが表示されます。具体的なエラーの詳細は共有フォルダ内に保存されるログファイルに記録されます（`~/monadic/data/error.log`）。

## 設定項目

設定項目には必須のものと任意の物があります。必須の設定項目が指定されていない場合は、アプリケーションの起動時にブラウザ画面上にエラーメッセージが表示されます。

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

## 関数・ツールの呼び出し

AIエージェントが使用するための関数・ツールを定義することが可能です。大きく分けて、1）Rubyによるメソッドの実行、2）コマンドやシェルスクリプトの実行、3）プログラム・コードの実行という3つの方法があります。

### Rubyによるメソッドの実行

次のようにRubyによるメソッドを定義すると、AIエージェントが必要に応じてそれらを呼び出すことができます。

1. レシピ・ファイルの中でRubyによるメソッド（関数）を定義
2. `@settings`の`tools`に関数名や引数などをJSONスキーマで指定
3. `initial_prompt`にメソッド（関数）の使用方法を記述

`@settings`の`tools`に関数名や引数を指定する方法の詳細は、使用する言語モデルによって異なります。下記を参考にしてください。

- OpenAI GPT-4: [Function calling guide](https://platform.openai.com/docs/guides/function-calling/function-calling-with-structured-outputs)
- Anthropic Claude: [Tool use (function calling)](https://docs.anthropic.com/en/docs/build-with-claude/tool-use)
- Cohere Command R:  [Tool use](https://docs.cohere.com/docs/tools)
- Mistral AI:  [Function calling](https://docs.mistral.ai/capabilities/function_calling/)

### コマンドやシェルスクリプトの実行

各コンテナで利用可能な特定のコマンドやシェルスクリプトを実行したい時は、すべての追加アプリの基底クラスである`MonadicApp`に定義されている`send_command`メソッドを使用してください。コマンドやシェルスクリプトは、コンテナ内の（`/monadic/data`）をカレント・ワーキング・ディレクトリとして実行されます。ホストコンピュータの共有フォルダ内の`scripts`ディレクトリに保存されたシェルスクリプトは、コンテナ内でパスが通っており、スクリプト名を指定するだけで実行することができます。

`send_command`メソッドの引数にはコマンド名（またはシェルスクリプト名）、コンテナ名、および成功時のメッセージを指定します。戻り値はコマンドの実行結果の文字列です。

```ruby
send_command(command: "ls", container: "python", success: "Linux ls command executed successfully")
```

例として、上記のコードはPythonコンテナ内で`ls`コマンドを実行し、その結果を返します。`command`引数は実行するコマンドを指定します。`container`引数はコマンドを実行するコンテナを略記で指定します。`python`と指定した場合は`monadic-chat-python-container`を指定することになります。`success`引数はコマンドの実行が成功した場合に、コマンドの実行結果の文字列の前に挿入するメッセージを指定します。成功時のメッセージは省略可能ですが、適切なメッセージを指定することで、AIエージェントがコマンドの実行結果を正しく解釈できるようになります。`success`引数が省略されたときは "Command executed successfully" というメッセージが表示されます。

?> AIエージェントに直接`send_command`を呼び出すように設定することも可能ですが、適切にエラー処理を行うため、Rubyでラッパーメソッドをレシピファイル内に作成して、それをJSONスキーマで指定すると共に`initial_prompt`に使用方法を記述してAIエージェントに使い方を示すやり方をお勧めします。


### プログラム・コードの実行

Rubyだけで書けるメソッドであれば、レシピファイル中に記述して、AIエージェントに呼び出させることができます。しかし、Pythonなどの他のプログラミング言語で書かれたプログラムを実行したい場合は、`send_code`メソッドを使用してください。

?> `send_code`メソッドはPythonコンテナ（`monadic-chat-python-container`）におけるコードの実行のみサポートしています。

`send_code`メソッドは、コンテナ内でプログラムのコードを実行するためのメソッドです。与えられたコードを一時ファイルに保存し、指定されたプログラムでそのファイルを実行します。`code`引数にはコードを文字列で指定します。`command`引数には、コードを実行するプログラムを指定します。`extension`引数には、一時ファイルの拡張子を指定します。`success`引数には、コードの実行が成功した場合に、コードの実行結果の文字列の前に挿入するメッセージを指定します。成功時のメッセージは省略可能ですが、適切なメッセージを指定することで、AIエージェントがコードの実行結果を正しく解釈できるようになります。`success`引数が省略されたときは "The code has been executed successfully." というメッセージが表示されます。

```ruby
send_code(code: "print('Hello, World!')", command: "python", extension: "py", success: "Python code executed successfully")
```

例として、上記のコードはPythonコンテナ内で`print('Hello, World!')`コードを実行し、その結果を返します。

`send_code`メソッドは、コード実行後に新しいファイルが生成されたかどうかを検知し、新しいファイルが生成された場合は、そのファイル名を返します。ファイルが生成されなかった場合は、`success` 引数で指定されたメッセージとコードの実行結果のみを返します。

**ファイルが生成されていない場合**

```text
The code has been executed successfully; Output: OUTPUT_TEXT
```

**ファイルが生成されている場合**

```text
The code has been executed successfully; File(s) generated: NEW_FILE; Output: OUTPUT_TEXT
```

生成されたファイルの情報を正しく得ることで、AIエージェントはさらにそれらを用いた処理を続けて行うことができます。

?> `send_code`をAIエージェントから直接呼び出すように設定すると、AIエージェントが必須の引数のいずれかを指定しない場合にコンテナ内でエラーが発生します。そのため、`send_command`を呼び出す際には、エラー処理を適切に行うようにしてください。`MonadicApp`クラスには、`run_command`というラッパーメソッドが用意されており、使用方法は`send_command`と同様ですが、引数が足りない場合にメッセージを返すようになっています。