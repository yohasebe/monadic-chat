# Monadic DSL （ドメイン固有言語）

Monadic DSL は、アプリの動作、画面、ツールを定義します。このページでは、その書き方を説明します。

## はじめに

Monadic DSL は Ruby にもとづく宣言的な形式で、Ruby のクラスを自分で書かずにアプリを定義できます。

## ファイル形式

アプリは `.mdsl` ファイル（Monadic Domain Specific Language）で定義します。Monadic Chat は、ファイルごとに、アプリの名前の Ruby のクラスを作ります。

## 基本構造

MDSL のアプリの定義の基本形は次のとおりです。

```ruby
app "AppNameProvider" do  # The name of the generated class (e.g., ChatOpenAI)
  description "A brief description of what this application does"

  icon "fa-solid fa-icon-name"  # Font Awesome class or icon name

  llm do
    provider "anthropic"
    model "<model-id>"
    temperature 0.7
  end

  system_prompt <<~PROMPT
    Instructions for the AI model that define how it should behave
    in this specific application context.
  PROMPT

  features do
    auto_speech false
  end
end
```

`llm` ブロックは、`tools` と `import_shared_tools` より前に書きます。ツールの定義は、宣言した時点で設定されているプロバイダーの形式に変換され、`llm` ブロックで設定するまで、プロバイダーは `openai` だからです。

## 設定ブロック

### 1. アプリのメタデータ

```ruby
app "AppNameProvider" do  # e.g., "ChatOpenAI", "CodingAssistantClaude", "ResearchAssistantGemini"
  description "Application description"
  # Or one description per UI language:
  # description do
  #   en "Application description"
  #   ja "アプリの説明"
  # end

  # Icon formats:
  icon "brain"                        # Simple name (becomes fa-solid fa-brain)
  # icon "github"                     # Known brand (becomes fa-brands fa-github)
  # icon "fa-regular fa-envelope"     # Full Font Awesome class with style prefix
  # icon "regular envelope"           # Style + name (becomes fa-regular fa-envelope)

  # For available icons, see: https://fontawesome.com/v6/search?ic=free

  display_name "Application Name"      # Name shown in the UI (default: the app name)
end
```

メニューのグループは、`features` ブロックで設定します（`group "Category Name"`）。既定はプロバイダーのグループです。

### 2. LLM設定

```ruby
llm do
  provider "anthropic"  # AI provider (anthropic, openai, cohere, etc.)
  model "<model-id>"  # Model name
  temperature 0.7  # Response randomness (0.0-2.0, default 0.7)
  max_tokens 4000  # Maximum response length
  reasoning_effort "high"  # Reasoning depth for reasoning-capable models
                           # (e.g., "low", "medium", "high"; when omitted,
                           # defaults to "none" = reasoning disabled)
end
```

モデルに送る直近のメッセージの数は、`features` ブロックの `context_size` で設定します。[機能フラグ](#feature-flags)を参照してください。

対応するプロバイダー：
- `anthropic`（Claude のモデル）
- `openai`（GPT のモデル）
- `cohere`（Command のモデル）
- `mistral`（Mistral のモデル）
- `gemini`（Google Gemini のモデル）
- `deepseek`（DeepSeek のモデル）
- `xai`（Grok のモデル）
- `ollama`（Ollama のローカルのモデル）

どのアプリがどのモデルで使えるかは、基本アプリのドキュメントの[プロバイダー別のアプリの対応状況](../basic-usage/basic-apps.md#app-availability)を参照してください。

#### モデル指定のベストプラクティス :id=model-specification-best-practices

**モデルを固定する**

```ruby
llm do
  provider "openai"
  model "<model-id>"
end
```

**既定のモデルを使う**

モデルを固定する必要がなければ、`llm` ブロックで `model` を省きます。

```ruby
llm do
  provider "openai"
end
```

モデルは下の順で決まり、アプリの定義にモデルの名前を書く必要はありません。

**設定の優先順位**

モデルは次の順（高いものから）で決まります。

1. **MDSL に書いた値**：`model "<model-id>"`（最優先）
2. **環境変数**：たとえば `~/monadic/config/env` の `OPENAI_DEFAULT_MODEL`
3. **プロバイダーの既定値**：`model_spec.js` の `providerDefaults`

**いくつものモデルから選ばせる**

配列で書くと、利用者がモデルを選べます。

```ruby
llm do
  provider "openai"
  model ["<model-1>", "<model-2>", "<model-3>"]  # Users can select from dropdown
end
```

**プロバイダーごとの環境変数**

プロバイダーごとに、次の環境変数があります。

| プロバイダー | 環境変数 |
|--------------|----------|
| OpenAI | `OPENAI_DEFAULT_MODEL` |
| Anthropic/Claude | `ANTHROPIC_DEFAULT_MODEL` |
| Gemini/Google | `GEMINI_DEFAULT_MODEL` |
| Mistral | `MISTRAL_DEFAULT_MODEL` |
| Cohere | `COHERE_DEFAULT_MODEL` |
| DeepSeek | `DEEPSEEK_DEFAULT_MODEL` |
| xAI/Grok | `GROK_DEFAULT_MODEL` |
| Ollama | `OLLAMA_DEFAULT_MODEL` |

### 3. システムプロンプト

```ruby
system_prompt <<~PROMPT
  You are an AI assistant specialized in helping with math problems.
  Always show your work step by step.
PROMPT
```

### 4. 機能フラグ :id=feature-flags

```ruby
# Interface features:
features do
  group "My Apps"         # Group in the app menu (default: the provider's group)
  disabled false          # Hide the app from the menu when true
  context_size 20         # Number of recent messages sent to the model
  auto_speech false       # Enable automatic text-to-speech for assistant messages
  easy_submit true        # Enable submitting messages with Enter key (without clicking Send)
  math true               # Enable mathematical notation rendering using KaTeX
  abc true                # Enable ABC music notation rendering and playback
  mermaid true            # Enable Mermaid diagram rendering for flowcharts and diagrams
  websearch true          # Enable web search
  library_save false      # No saving to the Knowledge Base (default true)
  library_search false    # No Knowledge Base retrieval (default true; needs library_save)
end

# Features that require specific implementation in the app:
features do
  # The following features are tied to specific system components:

  pdf_vector_storage true # Enable PDF file upload and vector storage for RAG (Retrieval-Augmented Generation)
  toggle true             # Render <div class='toggle'> blocks in assistant messages as collapsible show/hide sections
  jupyter true            # Enable access to Jupyter notebook interface
  image_generation true   # Enable AI image generation tools in conversation
  monadic true            # REQUIRED for Session State apps - enables context management via tools
  initiate_from_assistant true # Allow assistant to send first message in conversation
  autonomy "high"         # Set autonomy level: "high", "medium" (default), or "low"
  expressive_speech false # Opt this app out of Expressive Speech injection.
                          # Useful for apps with strict output formats (e.g. JSON-producing apps)
                          # where appended voice-marker instructions would collide with the system prompt.
                          # Default: not set (the feature activates automatically when Auto Speech is on
                          # and a marker-capable TTS provider is selected).

  # Speech-to-speech (Live Conversation family). Declaring speech_to_speech
  # replaces the text input panel with Start/Stop controls and streams the
  # microphone to the provider's realtime API. See the Live Conversation
  # section in Chat & Assistant Apps for the user-facing behavior.
  speech_to_speech true   # Turn this app into a speech-to-speech app
  sts_input_rate 16000    # Microphone sample rate in Hz. Default: 24000
                          # (Gemini Live consumes 16000)
  sts_vad_threshold 0.65  # Voice-activity detection sensitivity (0.0-1.0).
                          # Higher = less sensitive to background noise
  sts_vad_prefix_ms 300   # Audio kept before speech starts, in milliseconds
  sts_vad_silence_ms 1000 # Silence that ends a turn, in milliseconds
  sts_vad_type "semantic_vad"   # Turn-detection mode. Default: "server_vad"
                                # (silence-based). "semantic_vad" waits for
                                # semantic completion (OpenAI only)
  sts_vad_eagerness "low"       # How quickly semantic_vad ends a turn:
                                # low / medium / high / auto (OpenAI only)
  sts_idle_stop_seconds 180 # Stop the session after this much inactivity.
                            # Default: 180. Set 0 to disable
end
```

`sts_vad_*` を省くと、プロバイダー自身の既定値が使われます。すべてのプロバイダーがすべての項目を使うわけではありません（xAI は `sts_vad_prefix_ms` を使いません）。Live Conversation の OpenAI 版では、利用者がターン判定のメニューで `sts_vad_type` と `sts_vad_eagerness` を選べ、選んだ値は次のセッションから MDSL の既定値より優先されます。

#### 自律レベル

`autonomy` は、アシスタントが操作の前にどれだけ確認を求めるかを決めます。

| レベル | 動作 |
|--------|------|
| `"high"` | 確認せずにすぐ操作します。Plan-Approve-Execute の手順を省きます。意図があいまいなとき、パスワード、元に戻せない操作のときだけ止まります。 |
| `"medium"` | 既定の動作です。いくつもの手順がある作業では、Plan-Approve-Execute の手順を含む、ふつうの確認を行います。 |
| `"low"` | どの操作の前にも、利用者に確認を求めます。2 つ以上の手順がある作業では、必ず `propose_plan` を使います。 |

省くと、`"medium"` になります（プロンプトには何も加えられません）。Web Insight は、ブラウザーの操作を確認なしで続けられるように `"high"` を使っています。

### 5. ツール定義

ツールは、共有のツールグループを取り込むか、独自のツールを定義するかの 2 つの方法で用意します。

#### 共有ツールグループのインポート

共有のツールグループは、いくつものアプリで使える、関連するツールのまとまりです。

```ruby
# Import always-available tool groups
import_shared_tools :file_operations, visibility: "always"
import_shared_tools :python_execution, visibility: "always"

# Import conditionally-available tool groups
import_shared_tools :web_automation, visibility: "conditional"
```

**使えるツールグループ**：ツールグループは、共有ツールの登録簿（`lib/monadic/shared_tools/registry.rb`）で定義されています。グループの一覧、含まれるツール、使える条件は、[ツールグループ](tool-groups.md)を参照してください。

**visibility の値**：
- `always`：ツールは最初からモデルに送られます
- `conditional`（既定）：モデルが `request_tool` でグループを求めるまで、ツールは隠れています

環境にも左右されるグループがあります（たとえば、コンテナが動いていること、API キーがあること）。その条件は[ツールグループ](tool-groups.md)のページにあります。プロバイダーにない能力（画像や音声の入力など）が要るグループは、そのプロバイダーでは使われません。

#### 動的スキル（reachable_skills）

すべてのツールグループを最初から取り込む代わりに、`reachable_skills` で、会話の途中で必要になったときに使えるグループを宣言できます。モデルが `request_tool` で名前を指定して求めるまで、グループは隠れています。

```ruby
# Groups the app can unlock when the conversation calls for them
reachable_skills :web_search_tools, :image_analysis

# Or grant the curated pool of read-only safe groups in one line
reachable_skills :safe
```

`reachable_skills :group_a, :group_b` は、それぞれのグループを `visibility: "conditional"` で取り込むのと同じですが、意図がわかりやすくなります。詳しくは[ツールグループ](tool-groups.md)の「動的スキル」の節を参照してください。

#### カスタムツールの定義

アプリ独自の機能には、独自のツールを定義します。

```ruby
tools do
  define_tool "book_search", "Search for books by title, author, or ISBN" do
    parameter :query, "string", "Search terms (book title, author name, or ISBN)", required: true
    parameter :search_type, "string", "Type of search to perform", enum: ["title", "author", "isbn", "any"]
    parameter :category, "string", "Book category to filter results", enum: ["fiction", "non-fiction", "science", "history", "biography"]
    parameter :max_results, "integer", "Maximum number of results to return (default: 10)"
  end
end
```

**注意**：`parameter` は `default` のキーワードを受け付けません。既定値は説明の文に書いてください。

#### 共有ツールとカスタムツールの組み合わせ

1 つのアプリで、共有のツールグループと独自のツールの両方を使えます。

```ruby
# Import shared tools
import_shared_tools :file_operations, visibility: "always"

# Define custom tools
tools do
  define_tool "analyze_data", "Analyze data from file" do
    parameter :filename, "string", "Name of file to analyze", required: true
  end
end
```

### 6. コンテキストコンパクション

OpenAI のモデルで動くアプリでは、`compaction` ブロックで、サーバー側での会話のコンパクション（Responses API）を設定します。既定でオンで、しきい値は 150,000 トークンです。しきい値を変えるときとオフにするときだけ、このブロックを書きます。

```ruby
compaction do
  compact_threshold 180_000   # Custom token threshold
end

compaction false              # Opt out — rely on the context_size sliding window only
```

## アプリケーション例

### シンプルなチャットアプリケーション

```ruby
app "ChatClaude" do  # AppName + Provider
  description "Basic chat application with Claude"
  icon "fa-solid fa-comments"
  display_name "Chat"

  system_prompt <<~PROMPT
    You are a helpful assistant that provides accurate and concise information.
    Always be polite and respond directly to the user's questions.
  PROMPT

  llm do
    provider "anthropic"
    model "<model-id>"
    temperature 0.7
  end

  features do
    monadic false  # Disable Session State (context management)
    initiate_from_assistant true
  end
end
```

> **注意**：動く例は、`docker/services/ruby/apps/` のアプリを参照してください。

### コードインタープリタ付の数学チューター

```ruby
app "MathTutorOpenAI" do  # AppName + Provider
  description "AI assistant that helps solve math problems step-by-step"
  icon "fa-solid fa-calculator"
  display_name "Math Tutor"
  
  system_prompt <<~PROMPT
    You are a helpful math tutor. When presented with math problems:
    1. Analyze the problem carefully
    2. Explain your approach
    3. Show all steps of your work
    4. Verify the answer
    
    You can use Python code to perform calculations and create visualizations.
    Focus on teaching the concepts, not just providing answers.
  PROMPT
  
  llm do
    provider "openai"
    model ["<model-1>", "<model-2>"]  # Array of model IDs for user selection
    temperature 0.7
  end

  features do
    math true        # Enable math notation rendering
  end
  
  tools do
    # run_code comes from the :python_execution group
    import_shared_tools :python_execution, visibility: "always"
  end
end
```

## 高度な機能

### ツール/関数呼び出し

ツールは MDSL ファイルで定義します。独自のツールには、対応する `*_tools.rb` ファイルに同じ名前のメソッドが要ります。

#### ファイル構成

ツールの実装は、アプリの `.mdsl` ファイルと並べて置く `*_tools.rb` ファイルに書きます。フォルダの構成とファイルの名前の決まりは、アプリの開発のガイドの[ファイル構成パターン](develop_apps.md#file-structure-patterns)を参照してください。

**共有のツールグループを使うとき**：

`import_shared_tools` を使うと、メソッドは `lib/monadic/shared_tools/` の共有のモジュールから来ます。作られるアプリのクラスには、取り込んだグループのモジュールと、アプリの `<アプリ名>Tools` モジュールが含まれるので、ツールのファイルにはアプリ独自のメソッドだけを書きます。

```ruby
# apps/my_app/my_app_tools.rb
module MyAppTools
  def my_custom_tool(param:)
    # Implementation
  end
end
```

どのアプリにも `:file_operations` のグループが加わり、共有フォルダのファイルを読み書きできます。

#### ベストプラクティス

1. **共有のツールを使う**：よくある機能には、コードを重ねて書かずに `import_shared_tools` を使います
2. **ツールの定義をはっきり書く**：すべてのツールを MDSL ファイルで定義します
3. **実装のメソッドを合わせる**：独自のツールには、`*_tools.rb` に対応するメソッドを用意します
4. **わかりやすい名前を付ける**：ツールとパラメーターの名前で、何をするかがわかるようにします
5. **意味のある説明を書く**：いつ、どう使うかを AI がわかるようにします
6. **ツールの実装を試す**：使う前に、ツールが正しく動くか確かめます
7. **使える条件を確かめる**：`conditional` のツールでは、必要なものがそろっているか確かめます

DSL で定義した、AI が呼び出せるツール（関数）は、プロバイダーごとの形式に自動で変換されます。

```ruby
tools do
  define_tool "generate_image", "Generate an image based on a text description" do
    parameter :prompt, "string", "Text description of the image to generate", required: true
    parameter :style, "string", "Style of the image", required: false, enum: ["realistic", "cartoon", "sketch"]
    parameter :size, "string", "Size of the image", required: false, enum: ["small", "medium", "large"]
  end
end
```

### MDSLでのツールの実装

MDSL でのツールの実装は、ファサードパターンにもとづいて、次の形で行います。

1. **ツールの定義**：ツールは MDSL ファイルで定義します
2. **ツールの実装**：対応する `*_tools.rb` ファイルに、ファサードパターンでメソッドを書きます

最小の例です。ツールを MDSL ファイルで宣言し、ツールのファイルのファサードのメソッドで入力を確かめ、エラーを扱います。

```ruby
# my_app_openai.mdsl (excerpt)
tools do
  define_tool "mermaid_documentation", "Get mermaid.js syntax documentation" do
    parameter :diagram_type, "string", "Type of diagram (graph, sequence, flowchart, etc.)", required: true
  end
end
```

```ruby
# my_app_openai.mdsl (excerpt): fetch_web_content comes from this group
import_shared_tools :web_search_tools, visibility: "always"
```

```ruby
# my_app_tools.rb
module MyAppTools
  # Facade method with validation and error handling
  def mermaid_documentation(diagram_type: "graph")
    raise ArgumentError, "diagram_type is required" if diagram_type.to_s.empty?

    fetch_web_content(url: "https://mermaid.js.org/syntax/#{diagram_type}.html")
  rescue => e
    "❌ #{e.message}"
  end
end
```

パターンの説明と、`include_modules` で取り込んだヘルパーモジュールを包む書き方を含むひな形は、アプリの開発のガイドの[常にファサードパターンを使用](develop_apps.md#always-use-facade-pattern)を参照してください。完全な例（ファサードのメソッドがヘルパーモジュールを包む Wikipedia のアプリなど）は、[レシピ例](recipe-examples.md)を参照してください。

### Session Stateアプリ

Session State を使うと、アプリは明示的なツールの呼び出しで、会話のターンをまたいで文脈を保てます。進み具合を追う、情報を積み上げる、構造のある状態を保つ、といったアプリで役に立ちます。

#### Session Stateアプリの要件

Session State を使うアプリでは、features ブロックで `monadic true` を**必ず**設定します。

```ruby
app "MySessionStateOpenAI" do
  llm do
    provider "openai"
  end

  features do
    monadic true  # REQUIRED - enables Session State functionality
  end

  tools do
    # Define load/save tools for state management
    define_tool "load_context", "Load current context from session state" do
      parameter :session, "object", "Session object (automatically provided)", required: false
    end

    define_tool "save_context", "Save response and context to session state" do
      parameter :message, "string", "Your response message", required: true
      parameter :topics, "array", "Topics discussed (accumulated)", required: false
      parameter :notes, "array", "Important notes (accumulated)", required: false
    end
  end
end
```

#### 組み込みSession Stateアプリ

Session State を使うアプリには、Chat Plus、Research Assistant、Math Tutor、Novel Writer、Translate、Language Practice Plus、Voice Interpreter、Jupyter Notebook などがあります。

### コンテキストスキーマ（セッションコンテキスト）

Session State のアプリは明示的なツールの呼び出しで文脈を扱いますが、`context_schema` ブロックで**文脈の自動抽出**も使えます。会話から大事な情報を取り出し、サイドバーのパネルに表示します。

> **注意**：Session Context の説明の全体は、[Session Context](session-context.md) のガイドを参照してください。

#### 基本的な使い方

```ruby
app "MyAppOpenAI" do
  features do
    monadic true  # Required for context_schema
  end

  context_schema do
    field :topics, icon: "fa-tags", label: "Topics",
          description: "Main subjects discussed in conversation"
    field :people, icon: "fa-users", label: "People",
          description: "Names of people mentioned"
    field :notes, icon: "fa-sticky-note", label: "Notes",
          description: "Important facts and preferences to remember"
  end
end
```

#### フィールド定義

`context_schema` のフィールドには、次の項目を指定できます。

| 項目 | 型 | 必須 | 説明 |
|------|----|------|------|
| `name` | Symbol | はい | フィールドの識別子（最初の引数、例：`:topics`） |
| `icon` | String | いいえ | Font Awesome のアイコンのクラス（例：`"fa-tags"`） |
| `label` | String | いいえ | サイドバーに表示する名前（既定：名前の `_` を空白にし、最初の文字を大文字にしたもの） |
| `description` | String | いいえ | 何を取り出すかを抽出のエージェントに伝えます |

#### デフォルトスキーマ

`context_schema` のブロックがなく、`monadic true` が設定されているときは、既定のスキーマが使われます。

- **Topics**：話題にしたこと
- **People**：出てきた人の名前
- **Notes**：覚えておく事実

#### カスタムスキーマの例

```ruby
# For a Code Review app
context_schema do
  field :files_reviewed, icon: "fa-file-code", label: "Files",
        description: "Source code files that were reviewed"
  field :issues, icon: "fa-bug", label: "Issues",
        description: "Bugs and code problems identified"
  field :suggestions, icon: "fa-lightbulb", label: "Suggestions",
        description: "Improvement recommendations"
end
```

Session State（明示的なツールの呼び出し）と Session Context（自動の抽出）は、どちらも `monadic true` が必要で、1 つのアプリでいっしょに使えます。2 つの仕組みの比較と用語は、Monadic モードのドキュメントの[用語ガイド](monadic-mode.md#terminology-guide)を参照してください。

### プロバイダー固有のアダプター

DSL は、関数の定義を、プロバイダーごとの形式に自動で変換します。

- OpenAI：`type: "function"` で包んだ OpenAI の関数呼び出しの形式
- Anthropic：`input_schema` を持つ Claude のツールの形式
- Cohere：JSON Schema の `parameters` を持つ、OpenAI と同じ `type: "function"` の形式
- Mistral：Mistral の関数呼び出しの API の形式
- Gemini：`function_declarations` で包んだ Google Gemini の形式
- DeepSeek：DeepSeek の関数呼び出しの形式
- Grok（xAI）：Grok の関数呼び出しの形式

この変換があるので、ツールの定義は DSL で 1 度書けば、どのプロバイダーでも使えます。

**Font Awesome のアイコンについて**：`icon` には、Font Awesome 6 Free のどのアイコンでも使えます（https://fontawesome.com/v6/search?ic=free）。"brain" のような短い名前は、Font Awesome のクラスに変換されます。

## デバッグとテスト

DSL のアプリの問題を探すときは、次を確かめます。

1. Ruby の文法が正しいか（`end` が抜けていないか、字下げが正しいか）
2. `llm` ブロックがツールより前にあるか。説明、アイコン、システムプロンプトがあるか
3. ツールの定義の書き方が正しいか
4. 選んだ機能とプロバイダーの能力が合っているか

アプリの読み込みに失敗しても、ほかのアプリは読み込まれます。失敗したアプリと理由は、サーバーの出力（`docker logs monadic-chat-ruby-container`、開発モードではターミナル）に表示されます。さらに詳しいデバッグの出力には、設定で `EXTRA_LOGGING=true` にします。

## ベストプラクティス

1. **共有のツールを使う** - よくある機能には、コードを重ねて書かずに `import_shared_tools` を使います
2. **ツールのモジュールにアプリの名前を付ける** - `MyAppOpenAI` は `MyAppTools` モジュールを使います
3. **わかりやすい名前を付ける** - アプリとツールの名前がはっきりしていると、使いやすくなります
4. **システムプロンプトを絞る** - 用途ごとに、その用途に合った指示を書きます
5. **要るものだけをオンにする** - アプリで使わない機能はオンにしません
6. **使うプロバイダーで試す** - 選んだ LLM で動くか確かめます
7. **アプリを整理する** - `display_name` で、画面での表示をそろえます
8. **使える条件を確かめる** - `conditional` のツールでは、必要なものがそろっているか確かめます

## よくある問題と解決策

### 定義したツールが失敗する

**問題**：モデルがツールを呼ぶと、"undefined method" になります。

**解決策**：メソッドが `<アプリ名>Tools` モジュールにあるか、そのツールのグループを `import_shared_tools` で取り込んでいるかを確かめます。

```ruby
# Explicit tool definition in the MDSL file
tools do
  define_tool "my_tool", "Tool description" do
    parameter :param, "string", "Parameter description"
  end
end
```

```ruby
# my_app_tools.rb
module MyAppTools
  def my_tool(param: nil)
    # ...
  end
end
```

### プロバイダー固有の考慮事項 :id=provider-specific-considerations

- **関数の呼び出しの上限**：会話の 1 つのターンで 20 回まで（Mistral では 30 回）
- **コードの実行**：どのプロバイダーでも、`:python_execution` のグループの `run_code` を使います
- **配列のパラメーター**：OpenAI では、配列に `items` が必要です
- **エラーの防止**：エラーのパターンを見つける仕組みが、いつまでも続くやり直しを防ぎます
