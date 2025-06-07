# Monadic DSL （ドメイン固有言語）

Monadic DSLは、特定の動作、UI要素、機能を持つAIアプリケーションを簡単に作成するための仕組みです。このドキュメントではDSLの構文と使用方法について詳しく説明します。

## はじめに

Monadic DSLは、Ruby言語をベースとした設定システムで、高度なRubyコードを書かなくても、AI駆動のアプリケーションを簡単に定義できるようにします。DSLは宣言的なアプローチでアプリケーションの動作を指定します。

## ファイル形式

Monadic Chatは**`.mdsl`形式**（Monadic Domain Specific Language）をすべてのアプリ定義に使用します。この宣言的な形式により、クリーンで保守しやすいAI駆動アプリケーションを定義できます。

**重要**: 従来のRubyクラス形式（`.rb`ファイル）はサポートされなくなりました。すべてのアプリはMDSL形式を使用する必要があります。

## 基本構造

基本的なMDSLアプリケーション定義は次のようになります：

```ruby
app "AppNameProvider" do  # 命名規則に従う: AppName + Provider (例: ChatOpenAI, ResearchAssistantClaude)
  description "このアプリケーションが何をするかの簡単な説明"
  
  icon "fa-solid fa-icon-name"  # FontAwesomeアイコンまたはカスタムHTML
  
  system_prompt <<~PROMPT
    AIモデルがこの特定のアプリケーションコンテキストでどのように
    振る舞うべきかを定義する指示。
  PROMPT
  
  llm do
    provider "anthropic"
    model "claude-3-opus-20240229"
    temperature 0.7
  end
  
  features do
    image_support true
    auto_speech false
  end
end
```

## 設定ブロック

### 1. アプリのメタデータ

```ruby
app "アプリケーション名" do
  description "アプリケーションの説明"
  
  # アイコンはスマートマッチングで複数の形式で指定できます：
  icon "brain"                        # シンプルな名前（fa-solid fa-brainになります）
  # icon "github"                     # 既知のブランド（自動的にfa-brands fa-githubになります）
  # icon "envelope"                   # シンプルな名前（fa-solid fa-envelopeになります）
  # icon "fa-regular fa-envelope"     # スタイル接頭辞付きの完全なFontAwesomeクラス
  # icon "regular envelope"           # スタイル + 名前形式（fa-regular fa-envelopeになります）
  # icon "mail"                       # あいまい検索（envelopeなど最も近い一致を検索）
  # icon "<i class='fas fa-code'></i>" # カスタムHTMLはそのまま保持されます
  
  # 利用可能なアイコンは次をご覧ください: https://fontawesome.com/v5/search?ic=free

  # アプリの命名オプション：
  display_name "アプリケーション名"    # UI上に表示される名前（必須）
  
  group "カテゴリ名"  # UI上でのグループ化（オプション）
end
```

### 2. LLM設定

```ruby
llm do
  provider "anthropic"  # AIプロバイダー (anthropic, openai, cohere, etc.)
  model "claude-3-opus-20240229"  # モデル名
  temperature 0.7  # レスポンスのランダム性 (0.0-1.0)
  max_tokens 4000  # 最大レスポンス長
end
```

サポートされているプロバイダー：
- `anthropic` (Claudeモデル)
- `openai` (GPTモデル)
- `cohere` (Commandモデル)
- `mistral` (Mistralモデル)
- `gemini` (Google Geminiモデル)
- `deepseek` (DeepSeekモデル)
- `perplexity` (Perplexityモデル)
- `xai` (Grokモデル)

どのアプリがどのモデルと互換性があるかの完全な概要については、基本アプリのドキュメントの[モデル互換性](/ja/basic-usage/basic-apps.md#app-availability)セクションを参照してください。

### 3. システムプロンプト

```ruby
system_prompt <<~PROMPT
  あなたは数学問題を解くのを手助けする専門AIアシスタントです。
  常に段階的に解法を示してください。
PROMPT
```

### 4. 機能フラグ

```ruby
# 標準的なUI機能:
features do
  image true              # アシスタントの応答内の画像をクリック可能にする (新しいタブで開く)
  auto_speech false       # アシスタントメッセージの自動テキスト読み上げを有効にする
  easy_submit true        # Enterキーでのメッセージ送信を有効にする (送信ボタンクリック不要)
  sourcecode true         # 拡張されたソースコードハイライトを有効にする (別名: code_highlight)
  mathjax true            # MathJaxを使用した数学表記のレンダリングを有効にする
  abc true                # ABC音楽表記のレンダリングと再生を有効にする
  mermaid true            # フローチャートや図表のためのMermaidダイアグラムレンダリングを有効にする
  websearch true          # ウェブ検索機能を有効にする (別名: web_search)
end

# アプリ内での特定の実装が必要な機能:
features do
  # 以下の機能は特定のシステムコンポーネントと連携します:
  
  pdf true                # PDFファイルのアップロードと処理のためのUI要素を有効にする
  toggle true             # UI内の折りたたみ可能なJSON表示セクションを有効にする
  jupyter_access true     # Jupyterノートブックインターフェースへのアクセスを有効にする (別名: jupyter)
  image_generation true   # 会話内でのAI画像生成ツールを有効にする
  monadic true            # 拡張表示のための構造化JSONとしてレスポンスを処理する
  initiate_from_assistant true # 会話でアシスタントが最初のメッセージを送信できるようにする
end
```

### 5. ツール定義

```ruby
tools do
  define_tool "book_search", "タイトル、著者、またはISBNで書籍を検索する" do
    parameter :query, "string", "検索語句（書籍タイトル、著者名、またはISBN）", required: true
    parameter :search_type, "string", "実行する検索のタイプ", enum: ["title", "author", "isbn", "any"]
    parameter :category, "string", "結果をフィルタリングする書籍カテゴリ", enum: ["fiction", "non-fiction", "science", "history", "biography"]
    parameter :max_results, "integer", "返す最大結果数（デフォルト: 10）"
  end
end
```

**注意**: `parameter`メソッドは`default`キーワードをサポートしていません。デフォルト値は説明文に含めてください。

## アプリケーション例

### シンプルなチャットアプリケーション

```ruby
app "シンプルチャット" do
  description "Claudeを使用した基本的なチャットアプリケーション"
  icon "fa-solid fa-comments"
  
  system_prompt <<~PROMPT
    あなたは正確で簡潔な情報を提供する便利なアシスタントです。
    常に丁寧に、ユーザーの質問に直接応答してください。
  PROMPT
  
  llm do
    provider "anthropic"
    model "claude-3-haiku-20240307"
    temperature 0.7
  end
end
```

### コードインタープリタ付の数学チューター

```ruby
app "数学チューター" do
  description "数学問題を段階的に解決するAIアシスタント"
  icon "fa-solid fa-calculator"
  
  # UI表示を標準化するためにdisplay_nameを使用
  display_name "数学"
  
  system_prompt <<~PROMPT
    あなたは有能な数学チューターです。数学の問題が提示されたら：
    1. 問題を注意深く分析してください
    2. アプローチを説明してください
    3. すべての手順を示してください
    4. 答えを確認してください
    
    計算や視覚化のためにPythonコードを使用できます。
    答えだけではなく、概念を教えることに重点を置いてください。
  PROMPT
  
  llm do
    provider "anthropic"
    model "claude-3-opus-20240229"
    temperature 0.7
  end
  
  features do
    sourcecode true     # コードハイライトを有効にする (以前のcode_interpreter)
    image true          # レスポンス内のクリック可能な画像を有効にする
  end
  
  tools do
    tool "run_python" do
      description "数学問題を解くためのPythonコードを実行する"
      parameters do
        parameter "code", type: "string", description: "実行するPythonコード"
      end
    end
    
    tool "plot_graph" do
      description "視覚化のためのグラフを作成する"
      parameters do
        parameter "x_values", type: "array", items: { type: "number" }, description: "X軸の値"
        parameter "y_values", type: "array", items: { type: "number" }, description: "Y軸の値"
        parameter "title", type: "string", description: "グラフのタイトル"
      end
    end
  end
end
```

## 高度な機能

> MDSLの内部実装とその仕組みについて詳しく知りたい開発者の方は、[MDSLの内部実装](mdsl-internals.md)をご覧ください。

### MDSLツール自動補完システム

Monadic Chatには、Rubyの実装ファイルからMDSLツール定義を動的に生成する自動補完システムが含まれています。これにより手動作業を削減し、ツール定義と実装の一貫性を確保できます。

#### 自動補完の仕組み

1. **実行時検出**: MDSLファイルが読み込まれる際、システムは対応する`*_tools.rb`ファイルを自動的にスキャンします
2. **メソッド分析**: Rubyの実装ファイル内のパブリックメソッドがツール候補として分析されます
3. **型推論**: パラメータの型がデフォルト値や命名パターンから推論されます
4. **動的補完**: 不足しているツール定義がLLMの利用可能ツールに自動的に追加されます
5. **ファイル書き込み**: 自動生成された定義は、オプションでMDSLファイルに書き戻されます

#### 設定

`MDSL_AUTO_COMPLETE`環境変数で自動補完の動作を制御できます：

```bash
# デフォルト（基本的なロギング付きで自動補完が有効）
# MDSL_AUTO_COMPLETE=  # 未設定 - 'true'と同じ

# 基本的なロギング付きで自動補完を有効にする
export MDSL_AUTO_COMPLETE=true

# 詳細なデバッグ情報付きで自動補完を有効にする
export MDSL_AUTO_COMPLETE=debug

# 自動補完を完全に無効にする
export MDSL_AUTO_COMPLETE=false
```

#### ファイル構造の要件

自動補完システムは標準的なMonadic Chatのファイル命名規則で動作します：

```text
apps/app_name/
├── app_name_constants.rb    # オプション: 共有定数（ICON、DESCRIPTION等）
├── app_name_tools.rb        # ツールメソッドの実装
├── app_name_provider.mdsl   # MDSLインターフェース（例：app_name_openai.mdsl）
└── app_name_provider.mdsl   # 追加のプロバイダーバージョン
```

#### メソッド検出のルール

**含まれるメソッド:**
- `*_tools.rb`ファイル内のパブリックメソッド
- 除外パターンに一致しないメソッド
- 標準ツールリストにないメソッド

**除外されるメソッド:**
- プライベートメソッド（`private`キーワード以降）
- パターンに一致するメソッド: `initialize`, `validate`, `format`, `parse`, `setup`, `teardown`, `before`, `after`, `test_`, `spec_`
- 標準MonadicAppメソッド（自動検出）

#### 型推論

システムはデフォルト値から自動的にパラメータの型を推論します：

```ruby
def example_tool(text: "", count: 0, enabled: false, items: [], config: {})
  # text: "string", count: "integer", enabled: "boolean"
  # items: "array", config: "object"
end
```

#### 生成されるツール定義

自動生成されるMDSLツール定義の例：

```ruby
tools do
  # Rubyの実装から自動生成されたツール定義
  define_tool "count_num_of_words", "Count the num of words" do
    parameter :text, "string", "The text content to process"
  end
end
```

#### ユーザー定義プラグインのサポート

自動補完システムは組み込みアプリとユーザー定義プラグインの両方をサポートします：

**組み込みアプリ:** `docker/services/ruby/apps/`
**ユーザープラグイン:** `~/monadic/data/plugins/`（またはコンテナ内では`/monadic/data/plugins/`）

#### 開発ツール

**テスト用CLIツール:**
```bash
# アプリの自動補完をプレビュー
ruby bin/mdsl_tool_completer novel_writer

# ツールの一貫性を検証
ruby bin/mdsl_tool_completer --action validate app_name

# デバッグ情報付きで詳細分析
ruby bin/mdsl_tool_completer --action analyze --verbose app_name
```

**RSpecテスト:**
システムには`spec/app_loading_spec.rb`に包括的なテストが含まれています：
- ツール実装の検証
- 自動補完の一貫性チェック  
- システムプロンプト参照の検証
- マルチプロバイダーツールの一貫性

#### ベストプラクティス

1. **Rubyメソッドをシンプルに保つ**: 明確なパラメータ名と適切なデフォルト値を使用
2. **意味のあるデフォルト値を追加**: デフォルト値は型推論に役立ちます
3. **わかりやすいメソッド名を使用**: メソッド名は説明の生成に使用されます
4. **パブリックとプライベートを分離**: ヘルパーメソッドを除外するために`private`キーワードを使用
5. **自動補完をテスト**: CLIツールを使用して生成された定義を確認

#### トラブルシューティング

**よくある問題:**
- **自動補完が機能しない**: `MDSL_AUTO_COMPLETE`環境変数を確認
- **型推論が間違っている**: Rubyメソッド定義のデフォルト値を確認
- **メソッドが見つからない**: メソッドがパブリック（`private`キーワードより前）であることを確認
- **ファイルが見つからない**: ファイル命名規則がパターンと一致することを確認

**デバッグモード:**
```bash
export MDSL_AUTO_COMPLETE=debug
# Monadic Chatを再起動して詳細な自動補完ログを確認
```

### ツール/関数呼び出し

DSLはAIが呼び出せるツール（関数）の定義をサポートしています。これらは自動的に各プロバイダーに適した形式に変換されます。

```ruby
tools do
  tool "generate_image" do
    description "テキスト説明に基づいて画像を生成する"
    parameters do
      parameter "prompt", type: "string", description: "生成する画像のテキスト説明"
      parameter "style", type: "string", enum: ["realistic", "cartoon", "sketch"], description: "画像のスタイル"
      parameter "size", type: "string", enum: ["small", "medium", "large"], description: "画像のサイズ", required: false
    end
  end
end
```

### MDSLでのツールの実装

MDSLでのツール実装は、ファサードパターンを使用した構造化されたアプローチに従います：

1. **ツールの定義**: ツールはMDSLファイルで明示的に定義するか、Ruby実装から自動補完されます
2. **ツールの実装**: ファサードパターンを使用してコンパニオン`*_tools.rb`ファイルにメソッドを実装します

#### 推奨: 自動補完付きファサードパターン

最小限または空のツール定義でMDSLファイルを作成：

```ruby
# mermaid_grapher_openai.mdsl
app "MermaidGrapherOpenAI" do
  description "mermaid.js構文を使用して図を作成する"
  icon "diagram"
  display_name "Mermaid Grapher"
  
  system_prompt <<~PROMPT
    mermaid.jsを使用してデータを視覚化するのを手伝います。
    構文例を取得するにはmermaid_documentation関数を使用してください。
  PROMPT
  
  llm do
    provider "openai"
    model "gpt-4o-2024-11-20"
    temperature 0.0
  end
  
  features do
    mermaid true
    image true
  end
  
  tools do
    # ツールはmermaid_grapher_tools.rbから自動補完されます
  end
end
```

ファサードメソッドを含むツールファイルを作成：

```ruby
# mermaid_grapher_tools.rb
class MermaidGrapherOpenAI < MonadicApp
  # 検証とエラーハンドリング付きファサードメソッド
  def mermaid_documentation(diagram_type: "graph")
    raise ArgumentError, "diagram_type is required" if diagram_type.nil? || diagram_type.empty?
    
    begin
      result = fetch_web_content(url: "https://mermaid.js.org/syntax/#{diagram_type}.html")
      { success: true, content: result }
    rescue => e
      { success: false, error: e.message }
    end
  end
end
```

#### ファサードパターンを使用したヘルパーモジュール

プロバイダー間で共有される機能の場合：

```ruby
# wikipedia_openai.mdsl
app "WikipediaOpenAI" do
  description "Wikipedia記事を検索"
  icon "fa-brands fa-wikipedia-w"
  display_name "Wikipedia"
  
  system_prompt <<~PROMPT
    情報を検索するにはsearch_wikipediaを使用してください。
  PROMPT
  
  llm do
    provider "openai"
    model "gpt-4.1"
    temperature 0.3
  end
  
  features do
    group "OpenAI"
  end
  
  include_modules ["WikipediaHelper"]
  
  tools do
    # wikipedia_tools.rbから自動補完
  end
end
```

ヘルパーをラップするファサードメソッドを含むツールファイルを作成：

```ruby
# wikipedia_tools.rb
class WikipediaOpenAI < MonadicApp
  include WikipediaHelper
  
  # 検証付きファサードメソッド
  def search_wikipedia(search_query: "", language_code: "en")
    raise ArgumentError, "search_query is required" if search_query.empty?
    
    begin
      # ヘルパーモジュールメソッドを呼び出す
      super(search_query: search_query, language_code: language_code)
    rescue => e
      { error: e.message }
    end
  end
end
```


### プロバイダー固有のアダプター

DSLは異なるAIプロバイダーに対して適切な関数定義形式に自動的に変換し、各モデルプロバイダーの特定の要件とフォーマットを処理します：

- OpenAI: `type: "function"`構造を使用してOpenAIの関数呼び出し形式に変換
- Anthropic: `input_schema`プロパティを持つClaudeのツール形式に適応
- Cohere: Cohereのコマンドモデルの`parameter_definitions`形式にマッピング
- Mistral: Mistralの関数呼び出しAPIに対応したフォーマット
- Gemini: `function_declarations`構造を使用してGoogle Geminiモデル向けに構造化
- DeepSeek: DeepSeekの関数呼び出し形式に変換
- Perplexity: Perplexityの関数形式に適応
- Grok (xAI): 厳格な検証を持つGrokの関数形式にマッピング

この自動変換により、DSLでツール定義を一度記述するだけで、手動変換なしに異なるプロバイダー間で動作させることができます。

**FontAwesomeアイコンについての注意**: `icon`メソッドを使用してアイコンを指定する場合、FontAwesome 5 Freeの任意のアイコン名を使用できます。利用可能なアイコンは https://fontawesome.com/v5/search?ic=free で確認できます。システムは「brain」のような単純な名前を自動的に適切なスタイルの正しいHTMLに変換します。

## デバッグとテスト

DSLアプリのトラブルシューティング時には、次の点を確認してください：

1. 有効なRuby構文（`end`文の欠落がない、適切なインデントがある）
2. 必須設定ブロック（アプリ名、説明、システムプロンプト、llm）
3. 適切に書式設定されたツール定義
4. 選択した機能とプロバイダー機能の互換性

アプリの読み込みに失敗した場合、エラーログは`~/monadic/data/error.log`に保存されます。

## ベストプラクティス

1. わかりやすい名前と明確な指示を使用する
2. システムプロンプトは特定のユースケースに焦点を当てる
3. アプリケーションに必要な機能のみを有効にする
4. ツールのパラメータには詳細な説明を提供する
5. さまざまな入力でテストを徹底的に行う
6. 関連するアプリを論理的なグループに整理する

## 移行に関する注意

**重要**: 従来のRubyクラス形式はサポートされなくなりました。すべてのアプリはMDSL形式を使用する必要があります。

古いRubyクラス形式のカスタムアプリがある場合は、MDSLに変換する必要があります：

1. 各プロバイダー用に新しい`.mdsl`ファイルを作成
2. ツール実装をファサードパターンを使用して`*_tools.rb`ファイルに移動
3. ヘルパーモジュールには`include_modules`を使用
4. 古い`.rb`アプリファイルを削除

## よくある問題と解決策

### 空のツールブロックエラー

**問題**: 空の`tools do`ブロックは「Maximum function call depth exceeded」エラーを引き起こします。

**解決策**: ツールを明示的に定義するか、コンパニオン`*_tools.rb`ファイルを作成します：

```ruby
# オプション1: 明示的なツール定義
tools do
  define_tool "my_tool", "ツールの説明" do
    parameter :param, "string", "パラメータの説明"
  end
end

# オプション2: app_name_tools.rbを作成
class AppNameProvider < MonadicApp
  # ツールメソッドが自動補完されます
end
```

### プロバイダー固有の考慮事項

- **関数制限**: OpenAI/Geminiは最大20回の呼び出し、Claudeは最大16回をサポート
- **コード実行**: すべてのプロバイダが`run_code`を使用（以前はAnthropicが`run_script`を使用）
- **配列パラメータ**: OpenAIは配列に`items`プロパティが必要
  llm do
    provider "anthropic"
    model "claude-3-opus-20240229"
    temperature 0.7
  end
  
  features do
    image true
    sourcecode true
    pdf false
  end
  
  # その他の設定...
end
```
