# Monadic DSL （ドメイン固有言語）

Monadic DSLは、特定の動作、UI要素、機能を持つAIアプリケーションを簡単に作成するための仕組みです。このドキュメントではDSLの構文と使用方法について詳しく説明します。

## はじめに

Monadic DSLは、Ruby言語をベースとした設定システムで、高度なRubyコードを書かなくても、AI駆動のアプリケーションを簡単に定義できるようにします。DSLは宣言的なアプローチでアプリケーションの動作を指定します。

## ファイル形式

Monadic Chatは**`.mdsl`形式**（Monadic Domain Specific Language）をすべてのアプリ定義に使用します。この宣言的な形式により、クリーンで保守しやすいAI駆動アプリケーションを定義できます。

?> **重要**: アプリ名はRubyクラス名と正確に一致する必要があります。例えば、`app "ChatOpenAI"`は対応する`class ChatOpenAI < MonadicApp`が必要です。これにより適切なメニューグループ化と機能が保証されます。

## 基本構造

基本的なMDSLアプリケーション定義は次のようになります：

```ruby
app "AppNameProvider" do  # Rubyクラス名と正確に一致する必要があります（例: ChatOpenAI）
  description "このアプリケーションが何をするかの簡単な説明"
  
  icon "fa-solid fa-icon-name"  # FontAwesomeアイコンまたはカスタムHTML
  
  system_prompt <<~PROMPT
    AIモデルがこの特定のアプリケーションコンテキストでどのように
    振る舞うべきかを定義する指示。
  PROMPT
  
  llm do
    provider "anthropic"
    model "claude-3-5-sonnet-20241022"
    temperature 0.7
  end
  
  features do
    image true
    auto_speech false
  end
end
```

## 設定ブロック

### 1. アプリのメタデータ

```ruby
app "AppNameProvider" do  # Rubyクラス名と正確に一致する必要があります
  description "アプリケーションの説明"
  
  # アイコンはスマートマッチングで複数の形式で指定できます：
  icon "brain"                        # シンプルな名前（fa-solid fa-brainになります）
  # icon "github"                     # 既知のブランド（自動的にfa-brands fa-githubになります）
  # icon "fa-regular fa-envelope"     # スタイル接頭辞付きの完全なFontAwesomeクラス
  # icon "<i class='fas fa-code'></i>" # カスタムHTMLはそのまま保持されます
  
  # 利用可能なアイコンは次をご覧ください: https://fontawesome.com/v5/search?ic=free

  display_name "アプリケーション名"    # UI上に表示される名前
  
  # group "カテゴリ名"  # プロバイダーによって自動設定 - 必要でない限り上書きしない
end
```

### 2. LLM設定

```ruby
llm do
  provider "anthropic"  # AIプロバイダー (anthropic, openai, cohere, etc.)
  model "claude-3-5-sonnet-20241022"  # モデル名
  temperature 0.7  # レスポンスのランダム性 (0.0-1.0)
  max_tokens 4000  # 最大レスポンス長
end
```

サポートされているプロバイダー：
- `openai` - https://openai.com
- `anthropic` - https://anthropic.com (Claude)
- `gemini` - https://ai.google.dev (Google)
- `mistral` - https://mistral.ai
- `cohere` - https://cohere.com
- `deepseek` - https://deepseek.com
- `perplexity` - https://perplexity.ai
- `xai` - https://x.ai (Grok)
- `ollama` - https://ollama.ai (ローカルモデル)

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
# 一般的なUI機能:
features do
  image true              # UIでの画像処理と添付を有効にする
  auto_speech false       # アシスタントメッセージの自動テキスト読み上げを有効にする
  easy_submit true        # Enterキーでのメッセージ送信を有効にする
  sourcecode true         # 拡張されたソースコードハイライトを有効にする
  mathjax true            # MathJaxを使用した数学表記のレンダリングを有効にする
  abc true                # ABC音楽表記のレンダリングと再生を有効にする
  mermaid true            # Mermaidダイアグラムレンダリングを有効にする
  websearch true          # ウェブ検索機能を有効にする
end

# プロバイダー固有の機能:
features do  
  pdf_vector_storage true # PDFアップロードとRAG（検索拡張生成）を有効にする
  toggle true             # 折りたたみ可能セクションを有効にする（Claude/Gemini/Mistral/Cohere）
  jupyter_access true     # Jupyterノートブックインターフェースへのアクセスを有効にする
  image_generation true   # AI画像生成 - サポート値: true、"upload_only"、false
  monadic true            # 構造化JSONレスポンス（OpenAI/Ollama/DeepSeek/Perplexity/Grok）
  initiate_from_assistant true # AIメッセージで会話を開始（Claude/Gemini）
end

?> **重要**: `monadic`と`toggle`を両方有効にしないでください - これらは相互排他的です。
```

### 5. ツール定義

```ruby
tools do
  define_tool "book_search", "タイトル、著者、またはISBNで書籍を検索する" do
    parameter :query, "string", "検索語句（書籍タイトル、著者名、またはISBN）", required: true
    parameter :search_type, "string", "実行する検索のタイプ", required: false, enum: ["title", "author", "isbn", "any"]
    parameter :category, "string", "結果をフィルタリングする書籍カテゴリ", required: false, enum: ["fiction", "non-fiction", "science", "history", "biography"]
    parameter :max_results, "integer", "返す最大結果数（デフォルト: 10）", required: false
  end
end
```

**注意**: `parameter`メソッドは`default`キーワードをサポートしていません。デフォルト値は説明文に含めてください。

## アプリケーション例

### シンプルなチャットアプリケーション

```ruby
app "ChatClaude" do  # クラス名と正確に一致する必要があります
  description "Claudeを使用した基本的なチャットアプリケーション"
  icon "fa-solid fa-comments"
  display_name "チャット"
  
  system_prompt <<~PROMPT
    あなたは正確で簡潔な情報を提供する便利なアシスタントです。
    常に丁寧に、ユーザーの質問に直接応答してください。
  PROMPT
  
  llm do
    provider "anthropic"
    model "claude-3-5-sonnet-20241022"
    temperature 0.7
  end
  
  features do
    toggle true  # Claudeはトグルモードを使用
    initiate_from_assistant true
  end
end
```

### コードインタープリタ付の数学チューター

```ruby
app "MathTutorOpenAI" do  # クラス名と正確に一致する必要があります
  description "数学問題を段階的に解決するAIアシスタント"
  icon "fa-solid fa-calculator"
  display_name "数学チューター"
  
  system_prompt <<~PROMPT
    あなたは有能な数学チューターです。数学の問題が提示されたら：
    1. 問題を注意深く分析してください
    2. アプローチを説明してください
    3. すべての手順を示してください
    4. 答えを確認してください
    
    計算や視覚化のためにrun_code関数を使用してください。
    答えだけではなく、概念を教えることに重点を置いてください。
  PROMPT
  
  llm do
    provider "openai"
    model "gpt-4.1"
    temperature 0.7
  end
  
  features do
    sourcecode true     # コードハイライトを有効にする
    image true          # 画像表示を有効にする
    mathjax true        # 数式表記を有効にする
  end
  
  tools do
    # run_codeは標準ツール - 定義不要
    # コード実行のために自動的に利用可能
  end
end
```

## 高度な機能

> MDSLの内部実装とその仕組みについて詳しく知りたい開発者の方は、[MDSLの内部実装](mdsl-internals.md)をご覧ください。

### MDSLツール自動補完システム（実験的）

?> **警告**: これはデフォルトで無効になっている実験的機能です。本番環境では注意して使用してください。

Monadic Chatには、Rubyの実装ファイルからMDSLツール定義を動的に生成する自動補完システムが含まれています。これにより手動作業を削減し、ツール定義と実装の一貫性を確保できます。

#### 自動補完の仕組み

1. **実行時検出**: MDSLファイルが読み込まれる際、システムは対応する`*_tools.rb`ファイルを自動的にスキャンします
2. **メソッド分析**: Rubyの実装ファイル内のパブリックメソッドがツール候補として分析されます
3. **型推論**: パラメータの型がデフォルト値や命名パターンから推論されます
4. **動的補完**: 不足しているツール定義がLLMの利用可能ツールに自動的に追加されます
5. **ファイル書き込み**: 自動生成された定義は、オプションでMDSLファイルに書き戻されます

#### 設定

自動補完はデフォルトで無効です。この実験的機能を有効にするには`~/monadic/config/env`ファイルで設定します：

```
# 自動補完を有効にする（本番環境では推奨しません）
MDSL_AUTO_COMPLETE=true

# デバッグ情報付きで有効にする
MDSL_AUTO_COMPLETE=debug

# 明示的に無効にする（デフォルト）
MDSL_AUTO_COMPLETE=false
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
- **自動補完が機能しない**: `~/monadic/config/env`ファイルの`MDSL_AUTO_COMPLETE`設定を確認
- **型推論が間違っている**: Rubyメソッド定義のデフォルト値を確認
- **メソッドが見つからない**: メソッドがパブリック（`private`キーワードより前）であることを確認
- **ファイルが見つからない**: ファイル命名規則がパターンと一致することを確認

**デバッグモード:**
1. `~/monadic/config/env`ファイルに以下を追加：
```
MDSL_AUTO_COMPLETE=debug
```
2. Monadic Chatを再起動して詳細な自動補完ログを確認

### ツール/関数呼び出し

DSLはAIが呼び出せるツール（関数）の定義をサポートしています。これらは自動的に各プロバイダーに適した形式に変換されます。

```ruby
tools do
  define_tool "generate_image", "テキスト説明に基づいて画像を生成する" do
    parameter :prompt, "string", "生成する画像のテキスト説明", required: true
    parameter :style, "string", "画像のスタイル", required: false, enum: ["realistic", "cartoon", "sketch"]
    parameter :size, "string", "画像のサイズ", required: false, enum: ["small", "medium", "large"]
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

## デバッグのヒント

- アプリ読み込みエラーは`~/monadic/data/error.log`を確認
- アプリ名がクラス名と正確に一致しているか確認
- `monadic`と`toggle`が両方有効になっていないか確認
- 詳細なデバッグ出力には`EXTRA_LOGGING=true`を使用
- ツールのテストには`ruby bin/mdsl_tool_completer app_name`を使用

## ベストプラクティス

1. **命名規則に従う** - アプリ識別子はRubyクラス名と正確に一致する必要があります
2. **わかりやすい名前を使用** - 明確なアプリ名とツール名は使いやすさを向上させます
3. **システムプロンプトを集中させる** - 各ユースケースに特化した指示
4. **必要な機能のみ有効にする** - 不要な機能を有効にしない
5. **対象プロバイダーでテスト** - 選択したLLMとの互換性を確保
6. **アプリを論理的に整理** - 一貫したUI表示のためdisplay_nameを使用

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

- **関数制限**: すべてのプロバイダーが会話ターンあたり最大20回までの関数呼び出しをサポート
- **コード実行**: すべてのプロバイダが`run_code`を使用してコード実行
- **配列パラメータ**: OpenAIは配列に`items`プロパティが必要
- **エラー防止**: 組み込みのエラーパターン検出が無限リトライループを防止
