# アプリの開発

Monadic Chat には、独自のシステムプロンプトとツールを持つアプリを加えられます。このページでは、その方法を説明します。

## MDSL形式によるアプリ開発 :id=how-to-add-a-simple-app

アプリは、拡張子 `.mdsl` の MDSL（Monadic Domain Specific Language）ファイルで定義します。1 つの MDSL ファイルで、1 つのプロバイダー用のアプリを 1 つ定義します。Monadic Chat は MDSL ファイルから、アプリの名前（たとえば `MyAppOpenAI`）の Ruby のクラスを作り、そこにプロバイダーのヘルパーモジュールを含めます。

Ruby で書くツールのメソッドは、アプリの名前からプロバイダーの部分を除いて `Tools` を付けた名前のモジュールに置きます。アプリが `MyAppOpenAI` と `MyAppClaude` なら、モジュールは `MyAppTools` です。このモジュールがあると、どのプロバイダーのアプリのクラスにも自動で含められます。

**よくあるアプリの形**：
- **ツールのモジュール**：アプリ独自のツールを `<アプリ名>Tools` モジュールに書いた `*_tools.rb` ファイル（推奨）
- **共有のツール**：`import_shared_tools` で取り込むツールのグループ。[ツールグループ](tool-groups.md)を参照してください
- **モジュール**：`include_modules` で加えるそのほかのモジュール

**繰り返すエラー**：ツールが同じ種類のエラーで 3 回失敗すると、Monadic Chat はやり直しを止め、対処のしかたを表示します。モデルがいつまでもやり直すことはありません。

**ツールの要件**：
- システムプロンプトで触れるツールには、どれも `define_tool` のブロックか、取り込んだツールのグループが必要です。
- `define_tool` のパラメーターは、Ruby のメソッドのキーワード引数と一致させます。
- ツールの Ruby のメソッドは public にします。Monadic Chat が実行するのは、そのリクエストでモデルに渡したツールだけで、それ以外の名前の呼び出しにはモデルにエラーを返します。

### ファイル構成パターン :id=file-structure-patterns

**パターン A：いくつかのプロバイダーで定数を共有する**
```
apps/coding_assistant/
├── coding_assistant_constants.rb # Shared constants (ICON, DESCRIPTION, etc.)
├── coding_assistant_tools.rb     # CodingAssistantTools module
├── coding_assistant_openai.mdsl  # OpenAI app
├── coding_assistant_claude.mdsl  # Claude app
└── coding_assistant_gemini.mdsl  # Gemini app
```

**パターン B：MDSL だけ**
```
apps/simple_app/
└── simple_app_openai.mdsl # The whole app; no Ruby file is needed
```

**パターン C：ツールのモジュール（推奨）**
```
apps/novel_writer/
├── novel_writer_tools.rb         # NovelWriterTools module
├── novel_writer_openai.mdsl      # OpenAI app
└── novel_writer_mistral.mdsl     # Mistral app
```

### サポートファイルの命名規則

- **ツールを書くファイル**：`*_tools.rb`（例：`novel_writer_tools.rb`）
- **定数のファイル**：`*_constants.rb`（例：`coding_assistant_constants.rb`）

### MDSL形式の基本構造

MDSL の形式（すべてのブロックと設定）は、[Monadic DSL](monadic_dsl.md) を参照してください。

## アプリの追加手順

1. アプリの MDSL ファイルを作ります。アプリ独自のツールがあれば、`*_tools.rb` ファイルも作ります。
2. ファイルを共有フォルダの `apps` フォルダ（`~/monadic/data/apps`）に保存します。`apps` の下のどのフォルダでもかまいません。
3. Monadic Chat を再起動します。

読み込みの決まり：

- `.rb` ファイルは `.mdsl` ファイルより先に読み込まれます。
- 名前が `_` で始まるファイルは読み込まれません。
- `apps` の中の `test`、`helpers`、`services` という名前のフォルダにあるファイルは、アプリとしては読み込まれません。
- シンボリックリンクを通した先のファイルは読み込まれません。
- 開発モード（`rake server:debug`）では、共有フォルダのアプリとヘルパーは、サーバーを起動するシェルで `MONADIC_LOAD_USER_CODE=true` を設定したときだけ読み込まれます。

あるアプリの読み込みに失敗しても、ほかのアプリは読み込まれます。失敗したアプリとエラーは、サーバーの出力（`docker logs monadic-chat-ruby-container`、開発モードではターミナル）に表示されます。

## 高度なアプリの追加方法

- プロバイダーごとに MDSL ファイルを 1 つ作ります（例：`my_app_openai.mdsl`、`my_app_claude.mdsl`）。
- ツールのメソッドは、`my_app_tools.rb` の `MyAppTools` モジュールに書きます。
- MDSL の `tools do` ブロックで、すべてのツールを定義します。
- ツールのメソッドで、入力を確かめ、エラーを扱います。

共有フォルダの `helpers` フォルダと、`apps/<アプリ名>/helpers` にある Ruby のファイルは、アプリのファイルより先に読み込まれます。いくつかのアプリで使うモジュールは、そこに置きます。

Docker のコンテナを加えるときは、そのファイルを `services` フォルダに置きます。[Docker コンテナの追加](adding-containers.md)を参照してください。コンテナでコマンドを実行したり、Python のコードを実行したりするには、すべてのアプリの基底クラスである `MonadicApp` の `send_command` か `send_code` を使います（[関数・ツールの呼び出し](#calling-functions-in-the-app)を参照）。

これらをそろえると、フォルダは次のようになります。

```text
~/
└── monadic
    └── data
        ├── apps
        │   └── my_app
        │       ├── my_app_openai.mdsl
        │       ├── my_app_claude.mdsl
        │       ├── my_app_tools.rb
        │       └── my_app_constants.rb (optional)
        ├── helpers
        │   └── my_helper.rb
        └── services
            └── my_service
                ├── compose.yml
                └── Dockerfile
```

## MDSL開発のベストプラクティス

### 常にファサードパターンを使用 :id=always-use-facade-pattern

ツールは、入力を確かめ、実際の処理を呼び、モデルが読める結果を返すメソッドとして書きます。ツールは文字列を返します。失敗したときは、メッセージを `❌` で始めると、モデルがそれを利用者に伝えられます。

**ひな形：**

MDSL ファイル：
```ruby
# my_app_openai.mdsl
app "MyAppOpenAI" do
  description "My custom app"
  icon "fa-solid fa-rocket"
  display_name "My App"

  llm do
    provider "openai"
  end

  system_prompt "You are a helpful assistant."

  tools do
    define_tool "method_name", "Description of what this tool does" do
      parameter :required_param, "string", "Description of the parameter", required: true
      parameter :optional_param, "string", "Optional parameter description", required: false
    end
  end
end
```

**アプリの名前**：アプリの名前は `AppNameProvider` の形にします。
- `AppName` は、アプリの名前をパスカルケースで書いたもの
- `Provider` は `OpenAI`、`Claude`、`Gemini`、`Mistral`、`Cohere`、`Grok`、`DeepSeek`、`Ollama` のどれか
- 例：`ChatOpenAI`、`CodingAssistantClaude`、`ResearchAssistantGemini`

ツールのファイル：
```ruby
# my_app_tools.rb
module MyAppTools
  def method_name(required_param:, optional_param: nil)
    raise ArgumentError, "required_param is empty" if required_param.to_s.strip.empty?

    result = do_the_work(required_param, optional_param)
    "Done: #{result}"
  rescue ArgumentError => e
    "❌ #{e.message}"
  rescue StandardError => e
    "❌ method_name failed: #{e.message}"
  end

  private

  def do_the_work(required_param, optional_param)
    # ...
  end
end
```

### カスタムアプリのモデル指定

`llm` ブロックで `model` を省くと、プロバイダーの既定のモデルが使われます。

```ruby
llm do
  provider "openai"
end
```

既定のモデルは、`~/monadic/config/env` の `<PROVIDER>_DEFAULT_MODEL` で決まり、設定がなければ Monadic Chat のプロバイダーの既定値が使われます。順序の全体と、いくつものモデルを選べるメニューについては、[モデル指定のベストプラクティス](monadic_dsl.md#model-specification-best-practices)を参照してください。

### セッション安全性の確保

アプリのクラスごとにインスタンスは 1 つで、すべてのセッションで共有されます。そのため、インスタンス変数に入れたデータはセッションの間で共有されます。

#### ✅ DO: 純粋関数を使用する

ツールのメソッドは、パラメーターだけにもとづくようにします。

```ruby
module MyAppTools
  def my_tool(input:, uppercase: false)
    # Uses only parameters
    uppercase ? input.upcase : input
  end
end
```

#### ❌ DON'T: セッション状態にインスタンス変数を使用しない

セッションのデータをインスタンス変数に入れないでください。

```ruby
module MyAppTools
  def validate_code(code:)
    # WRONG: another session can overwrite this
    @last_validated_code = code
    validate(code)
  end

  def preview_code
    # WRONG: may read another session's code
    generate_preview(@last_validated_code)
  end
end
```

セッション A がコードを検証し、次にセッション B が別のコードを検証すると、セッション A で求めたプレビューにセッション B のコードが表示されます。

#### インスタンス変数の許容される使用法

すべてのセッションで同じ、読み取り専用の設定：

```ruby
module MyAppTools
  def my_tool(input:)
    process(input, max_length: app_config[:max_length])
  end

  private

  def app_config
    @app_config ||= { max_length: 1000 }.freeze  # OK: read-only, same for everyone
  end
end
```

#### ベストプラクティスまとめ

1. **状態を持たないツール**：呼び出しのたびに、入力から処理して結果を返します。
2. **データはパラメーターで渡す**：入力はすべて引数で渡します。
3. **結果はすべて返す**：結果を隠れた状態に残さず、返します。
4. **会話の状態には `session` を使う**：1 つの会話に属するデータ（たとえば最後に作ったファイルの名前）は、`session:` のキーワード引数で受け取ります。[Rubyによるメソッドの実行](#define-ruby-methods)を参照してください。
5. **残すデータはファイルに**：長く残すデータは、共有フォルダに書きます。
6. **インスタンス変数は読み取り専用だけ**：インスタンス変数は、すべてのセッションで同じ設定にだけ使います。

## よくある問題のトラブルシューティング

### メソッドが見つからないエラー

ツールの呼び出しが "undefined method" で失敗するとき：

1. モジュールの名前が、アプリの名前からプロバイダーの部分を除いて `Tools` を付けたものか確かめます（`MyAppOpenAI` → `MyAppTools`）。
2. メソッドの名前が `define_tool` の名前と一致しているか確かめます。
3. キーワード引数が `define_tool` のパラメーターと一致しているか確かめます。

## ヘルパーモジュール :id=helper-modules

アプリのクラスには、そのプロバイダーのヘルパーモジュールが含まれます。

- `OpenAIHelper` - OpenAI
- `ClaudeHelper` - Anthropic Claude
- `CohereHelper` - Cohere
- `MistralHelper` - Mistral AI
- `GeminiHelper` - Google Gemini
- `DeepSeekHelper` - DeepSeek
- `GrokHelper` - xAI Grok
- `OllamaHelper` - Ollama

どれでもツールの呼び出しが使えます（[関数・ツールの呼び出し](#calling-functions-in-the-app)を参照）。どのアプリがどのプロバイダーで使えるかは、[プロバイダー別のアプリの対応状況](../basic-usage/basic-apps.md#app-availability)を参照してください。

## 設定項目

アプリには次の設定が要ります。ない場合もアプリは読み込まれ、既定の値が使われて、アプリの説明に警告が表示されます。

`description`（文字列）
アプリの説明です。

`icon`（文字列）
アイコンです。`"fa-solid fa-rocket"` のような Font Awesome のクラスか、アイコンの名前を書きます。

`system_prompt`（文字列）
システムプロンプトです。

次の設定は省けます。

`display_name`（文字列）
画面に表示する名前です。既定はアプリの名前です。

`group`（文字列、`features do` の中）
アプリのメニューでのグループです。既定はプロバイダーのグループ（たとえば "OpenAI"）です。

```ruby
features do
  group "My Apps"
end
```

そのほかの設定は、[設定項目](./setting-items.md)を参照してください。

## 関数・ツールの呼び出し :id=calling-functions-in-the-app

ツールは MDSL ファイルの `tools do` ブロックで定義します。ツールの裏の処理は、次の 3 つのどれかで行います。1）ツールのモジュールの Ruby のメソッド、2）コンテナの中でのコマンドやシェルスクリプト、3）Python コンテナで実行するプログラムのコード。

### Rubyによるメソッドの実行 :id=define-ruby-methods

1. MDSL の `tools do` ブロックでツールを定義します。
2. ツールのモジュールに、同じ名前のメソッドを書きます。
3. メソッドのキーワード引数を、ツールのパラメーターと一致させます。

**`session` の引数：**
- メソッドが `session:` のキーワード引数を受け取るようになっていると、Monadic Chat は今の会話のセッションを渡します。`define_tool` で `session` を宣言する必要はありません。
- 1 つの会話に属する状態に使います。例：`session[:last_image_filename] = "image.png"`

ツールの定義の送り方と、1 つのターンでできるツールの呼び出しの数は、プロバイダーによって違います。[プロバイダー別の注意点](monadic_dsl.md#provider-specific-considerations)を参照してください。

### コマンドやシェルスクリプトの実行

`send_command` は、共有フォルダ（`/monadic/data`）を作業ディレクトリにして、コンテナの中でコマンドを実行します。

```ruby
send_command(command: "ls", container: "python", success_with_output: "Files in the shared folder:\n")
```

引数：
- `command`：実行するコマンド
- `container`：コンテナを短い形で書きます。`python` は `monadic-chat-python-container`、`my-service` は `monadic-chat-my-service-container` です
- `success`：コマンドが出力なしで成功したときに返すメッセージ（既定："Command has been executed."）
- `success_with_output`：出力があるとき、その前に付ける文（既定："Command has been executed with the following output: "）

Python コンテナでは、共有フォルダの `scripts` フォルダが、システムのフォルダの後ろで `PATH` に入っているので、そこに置いたスクリプトを名前で実行できます。

Ruby 側（`container: "ruby"`）で動くのは、Monadic Chat に付属の Ruby スクリプトだけです。

?> `send_command` と `send_code` は `MonadicApp` の private のメソッドです。まず引数を確かめるツールのメソッドから呼んでください。引数がおかしいとき、モデルにわかりやすいメッセージが届きます。

### プログラム・コードの実行

`send_code` は、Python コンテナ（`monadic-chat-python-container`）でプログラムのコードを実行します。コードを指定の拡張子のファイルに保存して、実行します。

```ruby
send_code(code: "print('Hello, world!')", command: "python", extension: "py", success: "Python code executed successfully")
```

引数は、コード（`code`）、コードを実行するコマンド（`command`、`python` など）、ファイルの拡張子（`extension`）、成功したときのメッセージ（`success`、既定は "The code has been executed successfully"）です。

結果には、コードが共有フォルダで作ったり変えたりしたファイルが示されます。

**新しいファイルがないとき：**

```text
The code has been executed successfully

NOTE: No image files were created. Do NOT display any images.

Output: OUTPUT_TEXT
```

**新しい画像のファイルがあるとき：**

```text
The code has been executed successfully

IMAGE FILES CREATED (verified to exist):
- /data/plot.png

These images are automatically displayed in the chat. Do NOT include <img> tags in your response.

Output: OUTPUT_TEXT
```

**そのほかの新しいファイルがあるとき：**

```text
The code has been executed successfully; File(s) generated or modified: /data/report.html

Output: OUTPUT_TEXT
```

?> `send_command` と同じく、`send_code` も、まず引数を確かめるツールのメソッドから呼んでください。

## 関数・ツール内でのLLMの使用

ツールから、`send_query` で独自にモデルにリクエストを送れます。`send_query` はプロバイダーのヘルパーモジュールにあり、アプリのプロバイダーの API を使います。`messages` の配列を含む API のパラメーターのハッシュと、`model:` のキーワード引数でモデルを渡します。`model:` を省くと、プロバイダーの既定のモデルが使われます。リクエストはストリーミングされません。

```ruby
# my_app_tools.rb
module MyAppTools
  def capital_of_argentina
    send_query(
      { "messages" => [{ "role" => "user", "content" => "What is the capital of Argentina?" }] },
      model: "<model-id>"  # optional
    )
  end
end
```

## MCP統合

Monadic Chat には、Monadic Conduit という MCP（Model Context Protocol）のサーバーがあります。`monadic_*` の名前の決まったツール（問い合わせ、Knowledge Base、メディアの分析と生成など）を公開し、アプリごとのツールは公開しません。アプリを作るときに、MCP のためにすることはありません。

サーバーの設定、ツール、クライアントの設定は、[MCP 統合](/ja/advanced-topics/mcp-integration.md)を参照してください。
