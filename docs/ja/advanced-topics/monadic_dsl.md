# Monadic DSL （ドメイン固有言語）

Monadic DSLは、特定の動作、UI要素、機能を持つAIアプリケーションを簡単に作成するための仕組みです。このドキュメントではDSLの構文と使用方法について詳しく説明します。

## はじめに

Monadic DSLは、Ruby言語をベースとした設定システムで、高度なRubyコードを書かなくても、AI駆動のアプリケーションを簡単に定義できるようにします。DSLは宣言的なアプローチでアプリケーションの動作を指定します。

## ファイル形式

Monadic Chatは2つの形式のアプリ定義をサポートしています：

1. **`.mdsl`ファイル** - よりシンプルで読みやすい構文のDSL形式
2. **`.rb`ファイル** - 従来のRubyクラス定義

`.mdsl`形式は、より簡潔で保守しやすいため、ほとんどのアプリケーションで推奨されます。

## 基本構造

基本的なMDSLアプリケーション定義は次のようになります：

```ruby
app "アプリケーション名" do
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
  app_name "アプリケーション完全名"     # 後方互換性のための従来のパラメータ
  display_name "アプリケーション名"    # UI上に表示される名前（推奨）
  
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
  tool "book_search" do
    description "タイトル、著者、またはISBNで書籍を検索する"
    parameters do
      parameter "query", type: "string", description: "検索語句（書籍タイトル、著者名、またはISBN）"
      parameter "search_type", type: "string", enum: ["title", "author", "isbn", "any"], description: "実行する検索のタイプ", required: false
      parameter "category", type: "string", enum: ["fiction", "non-fiction", "science", "history", "biography"], description: "結果をフィルタリングする書籍カテゴリ", required: false
      parameter "max_results", type: "integer", description: "返す最大結果数", required: false
    end
  end
end
```

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

MDSL形式を使用する場合、ツールの実装は2つの部分に分かれています：

1. **ツールの定義**: MDSLファイルで`define_tool`メソッドを使ってツールの構造を定義する
2. **ツールの実装**: 実際のメソッドを別のRubyファイルで実装する

#### 方法1: 同名のRubyファイルを使用する

まず、MDSLファイルでツールを定義します：

```ruby
# mermaid_grapher.mdsl
app "Mermaid Grapher" do
  description "mermaid.js構文を使用して図を作成する"
  icon "diagram"
  
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
  
  # ツールはここで定義されますが、実装は別の場所にあります
  tools do
    define_tool "mermaid_documentation", "特定のmermaidダイアグラムタイプのドキュメントと例を取得する" do
      parameter :diagram_type, "string", "mermaidダイアグラムのタイプ（例：flowchart、sequenceDiagramなど）", required: true
    end
  end
end
```

次に、同じベース名を持つRubyファイルを作成して、メソッドを実装します：

```ruby
# mermaid_grapher.rb
class MermaidGrapher < MonadicApp
  # 呼び出されるメソッドを実際に実装する
  def mermaid_documentation(diagram_type: "graph")
    fetch_web_content(url: "https://mermaid.js.org/syntax/#{diagram_type}.html")
  end
end
```

#### 方法2: ヘルパーモジュールを使用する

より複雑な実装や共有機能の場合：

```ruby
# wikipedia.mdsl
app "Wikipedia" do
  description "Wikipedia記事を検索"
  icon "fa-brands fa-wikipedia-w"
  
  system_prompt <<~PROMPT
    情報を検索するにはsearch_wikipediaを使用してください。
  PROMPT
  
  llm do
    provider "openai"
    model "gpt-4o"
    temperature 0.3
  end
  
  # ツールインターフェースを定義
  tools do
    define_tool "search_wikipedia", "Wikipedia記事を検索する" do
      parameter :search_query, "string", "検索クエリ", required: true
      parameter :language_code, "string", "言語コード", required: true
    end
  end
end
```

ヘルパーモジュールを含む最小限のアプリクラスを作成します：

```ruby
# wikipedia_app.rb
class Wikipedia < MonadicApp
  include WikipediaHelper  # 実際の実装を含むモジュール
end
```

そして、ヘルパーモジュールで実際の機能を実装します：

```ruby
# wikipedia_helper.rb
module WikipediaHelper
  def search_wikipedia(search_query: "", language_code: "en")
    # 実装コード...
    result = perform_search(search_query, language_code)
    return result
  end
  
  private
  
  def perform_search(query, language)
    # プライベートヘルパーメソッド...
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

## 従来のアプリスタイルからMDSLへの変換

従来のRubyクラス形式で既存のアプリがある場合は、新しいMDSL形式に変換することを推奨します。

**旧形式：**
```ruby
class MathTutorApp < MonadicApp
  include ClaudeHelper
  
  @settings = {
    app_name: "数学チューター",
    icon: "fa-solid fa-calculator",
    description: "数学問題を段階的に解決するAIアシスタント",
    initial_prompt: "あなたは有能な数学チューターです...",
    pdf: false,
    image: true,
    sourcecode: true,
    # その他の設定...
  }
  
  # カスタムメソッド...
end
```

**新しいMDSL形式：**
```ruby
app "数学チューター" do
  description "数学問題を段階的に解決するAIアシスタント"
  icon "calculator"  # アイコンはfa-solid接頭辞なしで簡略化された名前を使用できます
  
  system_prompt "あなたは有能な数学の先生です..."
  
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
