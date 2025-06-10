# アプリの開発

Monadic Chatでは、オリジナルのシステムプロンプトを用いたAIチャットボット・アプリケーションを開発することができます。このセクションでは、新しいアプリケーションを開発するための手順を説明します。

## MDSL形式によるアプリ開発

Monadic Chatでは、**MDSL（Monadic Domain Specific Language）形式**でアプリを開発します。この宣言的な形式により、シンプルで保守しやすいアプリが作成できます。

**重要**: 従来のRubyクラス形式はサポートされなくなりました。すべてのアプリはMDSL形式で作成する必要があります。

**MDSL自動補完機能**: Monadic ChatにはRubyの実装ファイルからツール定義を動的に生成する自動補完システムが含まれています。これにより手動作業を削減し、ツール定義と実装の一貫性を確保できます。

**一般的なアプリパターン**:
- **ファサードパターン**: すべてのカスタム機能にファサードメソッドを使用する`*_tools.rb`ファイルを持つアプリ（推奨）
- **モジュール統合**: 共有機能に`include_modules` + ファサードメソッドを使用するアプリ
- **標準ツール**: MonadicAppの組み込みメソッドのみを使用するアプリ

**エラー防止**: システムには無限リトライループを防ぐエラーパターン検出が含まれています：
- 繰り返されるエラー（フォント、モジュール、権限の問題）を検出
- 類似のエラーが3回発生すると停止
- コンテキストに応じた提案を提供

**重要**: 空の`tools do`ブロックは「Maximum function call depth exceeded」エラーを引き起こす可能性があります。必ずツールを明示的に定義するか、コンパニオン`*_tools.rb`ファイルを作成してください。

### MDSL形式のメリット

1. **シンプルな記述**: Rubyのコード記述を最小限に抑制
2. **プロバイダー対応**: 複数のLLMプロバイダーに対応しやすい
3. **保守性**: 設定とロジックが分離され管理しやすい
4. **一貫性**: 統一されたアプリ定義形式

### ファイル構成パターン

**パターンA: 定数共有型（複数プロバイダー対応）**
```
apps/coding_assistant/
├── coding_assistant_constants.rb # 共有定数（ICON、DESCRIPTION等）
├── coding_assistant_tools.rb     # ツール実装（ファサードパターン）
├── coding_assistant_openai.mdsl  # OpenAI専用設定
├── coding_assistant_claude.mdsl  # Claude専用設定
└── coding_assistant_gemini.mdsl  # Gemini専用設定
```

**パターンB: シンプル型（標準ツールのみ）**
```
apps/simple_app/
└── simple_app_openai.mdsl # 完全なMDSL定義（追加Rubyファイル不要）
```

**パターンC: ツール実装型（推奨）**
```
apps/novel_writer/
├── novel_writer_tools.rb         # ファサードパターンでのツール実装
├── novel_writer_openai.mdsl      # OpenAI用MDSL定義
└── novel_writer_claude.mdsl      # Claude用MDSL定義
```

### サポートファイルの命名規則

- **ツール実装ファイル**: `*_tools.rb` (例: `novel_writer_tools.rb`)
- **定数ファイル**: `*_constants.rb` (例: `coding_assistant_constants.rb`)

### MDSL形式の基本構造

```ruby
app "AppNameProvider" do      # プロバイダー付きのID（例: ChatOpenAI）
  display_name "アプリ名"     # UIに表示される名前（プロバイダー名なし）
  description <<~TEXT
    アプリの説明文
  TEXT
  icon "icon-name"
  
  llm do
    provider "openai"
    model "gpt-4"
    temperature 0.7
  end

  system_prompt <<~TEXT
    システムプロンプト
  TEXT

  features do
    easy_submit false
    auto_speech false
    image true
    group "OpenAI"      # UIでのグループ分け
  end

  # ツールが必要な場合（自動補完される場合は空でも可）
  tools do
    # ツールはtools.rbファイルから自動補完されます
  end
end
```

## アプリの追加手順

1. MDSLファイルを作成します
2. 共有フォルダの`apps`ディレクトリに保存します（`~/monadic/data/apps`）
3. Monadic Chatを再起動します

MDSLファイルは`apps`ディレクトリ以下の任意のディレクトリに保存できます。

## 高度なアプリの追加方法

堅牢なアプリ開発には、MDSLとファサードパターンを使用します：
- 各プロバイダー向けに`app_name_provider.mdsl`を作成（例: `chat_openai.mdsl`）
- MonadicAppを拡張するファサードメソッドを含む`app_name_tools.rb`を作成
- ファサードメソッドに入力検証とエラーハンドリングを含める
- 共有機能には`include_modules`とファサードラッパーを使用
- ファサードメソッドからの自動補完に依存

`helpers`フォルダ内のファイルはアプリファイルよりも先に読み込まれるため、アプリケーションの機能を拡張するためにヘルパーファイルを使用できます。これにより、共通の機能をモジュールとしてまとめ、複数のアプリで再利用できます。

標準コンテナ以外の新たなコンテナを追加したい場合は、`services`フォルダにDocker関連ファイルを格納します。コンテナ内で利用可能な特定のコマンドを実行したい時や、コードを実行したい場合は、すべての追加アプリの基底クラスである`MonadicApp`に定義されている`send_command`メソッドまたは`send_code`メソッドを使用します（詳細については[関数・ツールの呼び出し](#calling-functions-in-the-app)を参照してください）。

これらを組み合わせてアプリを定義する場合、次のようなフォルダ構成になります。

```text
~/
└── monadic
    └── data
        ├── apps
        │   └── my_app
        │       ├── my_app_openai.mdsl
        │       ├── my_app_claude.mdsl
        │       ├── my_app_tools.rb
        │       └── my_app_constants.rb （オプション）
        ├── helpers
        │   └── my_helper.rb
        └── services
            └── my_service
                ├── compose.yml
                └── Dockerfile
```

## プラグインの作成

共有フォルダ直下の`apps`、`helpers`、`services`にファイルを次々と追加していくと、コードの管理が難しくなったり、再配布することが難しくなる可能性があります。追加アプリを単一のフォルダ内にまとめて、パッケージ化されたプラグインとして開発することができます。

プラグインを作成するには、`~/monadic/data/plugins`以下にプラグインフォルダを作成し、その直下に`apps`やその他のフォルダを作成し、必要なファイルを格納します。

```text
~/
└── monadic
    └── data
        └── plugins
            └── my_plugin
                ├── apps
                │   └── my_app
                │       ├── my_app_openai.mdsl
                │       ├── my_app_claude.mdsl
                │       └── my_app_tools.rb
                ├── helpers
                │   └── my_helper.rb
                └── services
                    └── my_service
                        ├── compose.yml
                        └── Dockerfile
```

上記はアプリ、ヘルパー、サービスを含む、かなり複雑なプラグイン構造の例です。`helpers`や`services`フォルダを省略して、よりシンプルなプラグイン構造を作成することもできます。

## MDSL開発のベストプラクティス

### 常にファサードパターンを使用

保守性と堅牢性のあるMDSLアプリケーションのために：

**ファサードパターンの利点:**
- **明確なAPI**: 自動補完のための明示的なメソッドシグネチャ
- **入力検証**: 無効な関数呼び出しを防止
- **エラーハンドリング**: 一貫したエラーレスポンス形式
- **デバッグ**: メソッド呼び出しの追跡とログが容易
- **将来対応**: 実装が変更されてもインターフェースの安定性を保つ

**実装テンプレート:**

対応するMDSLファイルを作成：
```ruby
# my_app_openai.mdsl
app "MyAppOpenAI" do
  description "カスタムアプリ"
  icon "🚀"
  display_name "My App"
  
  llm do
    provider "openai"
    model "gpt-4o"
  end
  
  system_prompt "あなたは役立つアシスタントです。"
  
  tools do
    # ツールはmy_app_tools.rbから自動補完されます
  end
end
```

**アプリ命名規則の注意**: MDSLファイル内のアプリ名は`AppNameProvider`のパターンに従う必要があります：
- `AppName`はPascalCaseのアプリケーション名
- `Provider`は大文字化されたLLMプロバイダー名（例：`OpenAI`、`Claude`、`Gemini`）
- 例：`ChatOpenAI`、`CodingAssistantClaude`、`ResearchAssistantGemini`

ファサードパターンを使用したツールファイル：
```ruby
# my_app_tools.rb
class MyAppOpenAI < MonadicApp  # クラス名はMDSL内のアプリ名と一致する必要があります
  # 完全な検証とエラーハンドリングを持つファサードメソッド
  def method_name(required_param:, optional_param: nil)
    # 1. 入力検証
    validate_inputs!(required_param, optional_param)
    
    # 2. 実装の呼び出し
    result = underlying_implementation(required_param, optional_param)
    
    # 3. 構造化されたレスポンスを返す
    format_response(result)
  rescue StandardError => e
    handle_error(e)
  end
  
  private
  
  def validate_inputs!(required_param, optional_param)
    raise ArgumentError, "必須パラメータが不足" if required_param.nil?
    # 特定の検証を追加
  end
  
  def format_response(result)
    { success: true, data: result }
  end
  
  def handle_error(error)
    { success: false, error: error.message }
  end
end
```

## よくある問題のトラブルシューティング

### メソッドが見つからないエラー
「undefined method」エラーが発生した場合：

1. **ファサードメソッドの作成**: すべてのカスタムメソッドにファサードパターンを使用した`*_tools.rb`ファイルを使用
2. **モジュール統合の追加**: 共有機能には`include_modules`とファサードラッパーを使用
3. **クラス名の検証**: ツールファイルのクラス名がアプリIDと一致することを確認

**ファサードパターン修正例**:
```ruby
# app_name_tools.rb
class AppNameProvider < MonadicApp
  def custom_method(param:, options: {})
    # 入力検証
    raise ArgumentError, "パラメータが必要です" if param.nil?
    
    # 実装の呼び出し
    result = underlying_service.method(param, options)
    
    # 構造化されたレスポンスを返す
    { success: true, data: result }
  rescue StandardError => e
    { success: false, error: e.message }
  end
end
```

## レガシーRubyクラスアプローチ :id=writing-the-recipe-file

!> **注意**: 以下に説明するRubyクラスベースのアプローチはサポートされなくなりました。すべてのアプリは[Monadic DSL形式](/ja/advanced-topics/monadic_dsl.md)を使用する必要があります。このセクションは参考のために残されています。

### 歴史的背景

現在のMDSL専用アーキテクチャ以前は、アプリは`MonadicApp`を継承したRubyクラスとして定義され、設定は`@settings`インスタンス変数に記述されていました。

```ruby
class RobotApp < MonadicApp
  include OpenAIHelper
  @settings = {
    display_name: "Robot App",
    icon: "🤖",
    description: "This is a sample robot app.",
    initial_prompt: "You are a friendly robot that can help with anything the user needs. You talk like a robot, always ending your sentences with '...beep boop'.",
  }
end
```

言語モデルと連携するためのモジュールとして、下記が利用可能です。

- `OpenAIHelper`
- `ClaudeHelper`
- `CohereHelper`
- `MistralHelper`
- `GeminiHelper`
- `GrokHelper`
- `PerplexityHelper`
- `DeepSeekHelper`
- `OllamaHelper`

どのアプリがどのモデルと互換性があるかの完全な概要については、基本アプリのドキュメントの[モデル互換性](/ja/basic-usage/basic-apps.md#app-availability)セクションを参照してください。

?> `OpenAIHelper`、`ClaudeHelper`、`CohereHelper`、`MistralHelper`、`GeminiHelper`、`GrokHelper`、`DeepSeekHelper`では "function calling" や "tool use" の機能を使うことができます（[関数・ツールの呼び出し](#calling-functions-in-the-app)を参照）。関数呼び出しのサポートはプロバイダーによって異なります - 制限については各プロバイダーのドキュメントを確認してください。

!> レシピファイルがRubyスクリプトとして有効ではなく、エラーが発生する場合、Monadic Chatが起動せず、エラーメッセージが表示されます。具体的なエラーの詳細は共有フォルダ内に保存されるログファイルに記録されます（`~/monadic/data/error.log`）。

## 設定項目

設定項目には必須のものと任意の物があります。必須の設定項目が指定されていない場合は、アプリケーションの起動時にブラウザ画面上にエラーメッセージが表示されます。下記は必須の設定項目の例です。

`display_name` (string, 必須)

ユーザーインターフェースに表示されるアプリケーションの名前（必須）を指定します。

`icon` (string, 必須)

アプリケーションのアイコン（絵文字またはHTML）を指定します。

`description` (string, 必須)

アプリケーションの説明を記述します。

`initial_prompt` (string, 必須)

システムプロンプトのテキストを指定します。

`group` (string)

Web 設定画面の Base App セレクタ上でアプリをグループ化するためのグループ名を指定します。必須ではありませんが、独自のアプリを追加する場合には、基本アプリと区別するために何らかのグループ名を指定することが推奨されます。

これらの他に、任意の設定項目が多数あります。[設定項目](./setting-items.md)を参照してください。

## 関数・ツールの呼び出し :id=calling-functions-in-the-app

AIエージェントが使用するための関数・ツールを定義することが可能です。MDSL形式では、ツールは`tools do`ブロック内で定義するか、`*_tools.rb`ファイルから自動補完されます。基礎となる機能を実装するには：1）ツールファイルでRubyメソッドを定義、2）コマンドやシェルスクリプトの実行、3）Ruby以外の言語でプログラムコードの実行、の3つの方法があります。

### Rubyによるメソッドの実行

MDSLでは、AIエージェントが使用できるRubyメソッドを定義するには2つのアプローチがあります：

**オプション1: 自動補完（推奨）**
1. ファサードメソッドを含む`*_tools.rb`ファイルを作成
2. MDSLファイルの`tools do`ブロックを空または最小限にする
3. システムがRubyメソッドからツール定義を自動補完

**オプション2: 明示的定義**
1. MDSLファイルの`tools do`ブロックでツールを明示的に定義
2. `*_tools.rb`ファイルに対応するメソッドを実装
3. メソッドシグネチャがツール定義と一致することを確認

ツール定義の形式はプロバイダーによってわずかに異なります：
- OpenAI/Gemini: 最大20回の関数呼び出しをサポート
- Claude: 最大16回の関数呼び出しをサポート
- コード実行: すべてのプロバイダがコード実行に`run_code`を使用
- 配列パラメータ: OpenAIは`items`プロパティが必要

### コマンドやシェルスクリプトの実行

各コンテナで利用可能な特定のコマンドやシェルスクリプトを実行したい時は、すべての追加アプリの基底クラスである`MonadicApp`に定義されている`send_command`メソッドを使用してください。コマンドやシェルスクリプトは、コンテナ内の`/monadic/data`をカレント・ワーキング・ディレクトリとして実行されます。ホストコンピュータの共有フォルダ内の`scripts`ディレクトリに保存されたシェルスクリプトは、コンテナ内でパスが通っており、スクリプト名を指定するだけで実行することができます。

`send_command`メソッドの引数にはコマンド名（またはシェルスクリプト名）、コンテナ名、および実行完了時のメッセージを指定します。戻り値はコマンドの実行結果の文字列にメッセージを前置したものです。

```ruby
send_command(command: "ls", container: "python", success_with_output: "Linux ls command executed with the following output:\n")
```

例として、上記のコードはPythonコンテナ内で`ls`コマンドを実行し、その結果を返します。`command`引数は実行するコマンドを指定します。`container`引数はコマンドを実行するコンテナを略記で指定します。`python`と指定した場合は`monadic-chat-python-container`を指定することになります。`success`引数と`success_with_output`引数はコマンドの実行が成功した場合に、コマンドの実行結果の文字列の前に挿入するメッセージを指定します。成功時のメッセージは省略可能ですが、適切なメッセージを指定することで、AIエージェントがコマンドの実行結果を正しく解釈できるようになります。`success`引数が省略されたときは "Command has been executed" というメッセージが表示されます。`success_with_output`引数を省略した場合は"Command has been executed with the following output: "というメッセージが表示されます。

?> AIエージェントに直接`send_command`を呼び出すように設定することも可能ですが、適切にエラー処理を行うため、ツールファイル内にRubyでラッパーメソッドを作成し、ファサードパターンを使用することをお勧めします。`MonadicApp`クラスには`run_command`というラッパーメソッドが用意されており、引数が不足している場合に特定のメッセージを返します。ツールファイルで`run_command`を使用することを推奨します。


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

## 関数・ツール内でのLLMの使用

!> `0.9.37`以前のバージョンで用いていた`ask_openai`メソッドは、`MonadicApp`クラスの`send_query`メソッドに置き換えられました。

上記の方法で作成した、AIエージェントから呼び出される関数・ツールの中で、さらにAIエージェントへのリクエストを行いたい場合があります。そのような場合、`MonadicApp`クラスで利用可能な`send_query`メソッドを使うことができます。

`send_query`は、現在のアプリで使用している言語モデル（または同じベンダーによる言語モデル）のAPIを介してAIエージェントにリクエストを送信し、その結果を返します。APIのパラメターを設定したハッシュを引数として渡すことで、AIエージェントにリクエストを送信することができます。

APIパラメターのハッシュには`messages`キーとその値としてメッセージの配列を指定する必要があります。また`model`キーには使用する言語モデルを指定します。その言語モデルのAPIで利用できる各種パラメターも利用可能です。

`send_query`を用いたクエリーでは`stream`は`false`になります（デフォルトで`false`に設定済みですので、明示的に指定する必要はありません）。

ツールファイル内でRubyを使用して作成した関数・ツールの中で、`send_query`を使用する方法は次の通りです。

```ruby
# my_app_tools.rb
class MyAppOpenAI < MonadicApp
  def my_function
    # パラメータの設定
    parameters = {
      message: {
        model: "gpt-4o",
        messages: [
          {
            role: "user",
            content: "What is the name of the capital city of Argentina?"
          }
        ]
      }
    }
    # OpenAIにリクエストを送信
    send_query(parameters)
  end
end
```
