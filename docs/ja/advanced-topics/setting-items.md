# アプリケーション設定項目

Monadic Chatのアプリケーションは、`.mdsl`拡張子を持つMDSL（Monadic Domain Specific Language）ファイルで定義されます。これらの設定により、各アプリケーションの動作、外観、機能が構成されます。

## 基本的なMDSL構造

```ruby
app "AppNameProvider" do
  description "アプリの簡潔な説明"
  icon "fa-icon-name"
  display_name "表示名"
  
  llm do
    provider "provider_name"
    model "model_name"
    temperature 0.7
  end
  
  features do
    # 機能設定をここに記述
  end
  
  tools do
    # ツール定義をここに記述
  end
  
  system_prompt <<~TEXT
    システムプロンプトのテキストをここに記述
  TEXT
end
```

## 必須設定

### アプリ定義
- **`app "AppName"`** - アプリ識別子。Rubyクラス名と正確に一致する必要があります（例：`app "ChatOpenAI"`には`class ChatOpenAI`が必要）
- **`description`** - アプリケーションの目的の簡潔な説明
- **`icon`** - アイコン識別子（Font Awesomeクラスまたは組み込みアイコン名）
- **`system_prompt`** - AIモデルへのシステム指示

### LLM設定
`llm`ブロックは必須で、以下を含みます：
- **`provider`** - AIプロバイダー（openai、claude、geminiなど）
- **`model`** - 使用する特定のモデル

## オプション設定

### LLMブロックのオプション
- **`temperature`** - 応答のランダム性を制御。範囲と利用可否はプロバイダーとモデルに依存。一部のモデル（OpenAI o1/o3、Gemini 2.5思考型モデルなど）は温度調整をサポートしません
- **`max_tokens`** - レスポンスの最大トークン数（利用可否と上限はモデルにより異なる）
- **`presence_penalty`** - 繰り返しトピックのペナルティ。一部のOpenAIおよびMistralモデルでサポート
- **`frequency_penalty`** - 繰り返し単語のペナルティ。一部のOpenAIおよびMistralモデルでサポート

### Featuresブロック
featuresブロック内のすべての設定はオプションです：

#### 表示とインタラクション
- **`display_name`** - UIに表示される名前（デフォルトはアプリ名）
- **`group`** - UIでアプリを整理するためのメニューグループ名。デフォルトでは、アプリはプロバイダーごとに自動的にグループ化されます（例：「OpenAI」、「Anthropic」）。カスタムグループを作成するために上書きできますが、デフォルトのプロバイダーベースのグループ化を維持することを推奨します
- **`disabled`** - trueの場合、メニューからアプリを非表示
- **`easy_submit`** - Enterキーのみでメッセージ送信
- **`auto_speech`** - AI応答を音声として自動再生
- **`initiate_from_assistant`** - AIメッセージで会話を開始

#### コンテンツ機能
- **`pdf_vector_storage`** - RAG（検索拡張生成）のためのPDFデータベース機能を有効化。UIにPDFインポートボタンとデータベースパネルを表示
- **`file`** - テキストファイルアップロードを有効化
- **`websearch`** - ウェブ検索機能を有効化
- **`image_generation`** - AI画像生成機能を有効化。以下の値を受け付けます：
  - `true` - 完全な画像生成機能（作成、編集、バリエーション）
  - `"upload_only"` - 画像アップロードのみ（生成・編集なし）
  - `false` - 無効（デフォルト）
- **`mermaid`** - Mermaidダイアグラムレンダリングを有効化
- **`abc`** - ABC音楽記譜法を有効化
- **`sourcecode`** - シンタックスハイライトを有効化
- **`mathjax`** - LaTeX数式レンダリングを有効化

#### コンテキスト管理
- **`context_size`** - 含める過去のメッセージ数
- **`monadic`** - JSONベースの状態管理を有効化（OpenAI/Ollamaのみ）
- **`toggle`** - 折りたたみ可能セクションを有効化（Claude/Gemini/Mistral/Cohere）
- **`prompt_suffix`** - すべてのユーザーメッセージに追加されるテキスト

?> **重要**: `monadic`と`toggle`を両方有効にしないでください - これらは相互排他的でプロバイダー固有です。

### Toolsブロック
AIが使用できる関数を定義：

```ruby
tools do
  define_tool "tool_name", "ツールの説明" do
    parameter :param_name, "type", "説明", required: true
  end
end
```

### 高度な設定
- **`response_format`** - 構造化出力形式を指定（OpenAI）
- **`reasoning_effort`** - 推論モデル用："low"（デフォルト）、"medium"、"high"
- **`models`** - 利用可能なモデルリストを上書き
- **`jupyter`** - Jupyterノートブックアクセスを有効化（Serverモードでは`ALLOW_JUPYTER_IN_SERVER_MODE=true`を設定しない限り無効）

!> **重要**: `jupyter`機能はUIの機能を有効にするだけです。実際のJupyter機能を使用するには、アプリで対応するツール定義（`run_jupyter`、`create_jupyter_notebook`など）を実装する必要があります。例については、Jupyter Notebookアプリの実装を参照してください。

## プロバイダー固有の動作

### OpenAI
- 構造化出力のための`monadic`モードをサポート
- **標準モデル**は`temperature`、`presence_penalty`、`frequency_penalty`をサポート
- **推論モデル**（パターン：/^o[13](-|$)/i）は自動的に`reasoning_effort`を使用
  - モデル：o1、o1-mini、o1-preview、o1-pro、o3、o3-pro、o4シリーズ
  - temperature、ペナルティ、ファンクションコーリングなし（ほとんどのモデル）
  - 一部はストリーミングをサポートしない（o1-pro、o3-pro）

### Claude
- コンテキスト表示に`toggle`モードを使用
- `initiate_from_assistant: true`が必要
- **Claude 4.0**モデルは`reasoning_effort`を`budget_tokens`に変換してサポート

### Gemini
- `toggle`モードを使用
- `initiate_from_assistant: true`が必要
- **推論モデル**（パターン：/2\.5.*preview/i）は`budgetTokens`を使用した`thinkingConfig`を使用
  - reasoning_effortマッピング：low=30%、medium=60%、high=80%（max_tokensの）
- **標準モデル**は温度調整をサポート

### Mistral
- `toggle`モードを使用
- **Magistralモデル**（パターン：/^magistral(-|$)/i）は`reasoning_effort`を直接使用
  - モデル：magistral-medium、magistral-small、magistralバリアント
  - 思考ブロックを出力から除去、LaTeX形式を変換
- `initiate_from_assistant: false`が必要
- `presence_penalty`と`frequency_penalty`をサポート

## システムレベル設定

これらはMDSLファイルではなく、Monadic Chat UIで設定されます：

- **`AI_USER_MODEL`** - AI生成ユーザーメッセージ用のモデル
- **`AI_USER_MAX_TOKENS`** - ユーザーメッセージ生成の最大トークン数（デフォルト：2000）
- **`WEBSEARCH_MODEL`** - ウェブ検索用のモデル（gpt-4.1-miniまたはgpt-4.1）
- **`STT_MODEL`** - 音声認識モデル
- **`ROUGE_THEME`** - シンタックスハイライトテーマ

## CONFIGとENVの使用パターン :id=config-env-pattern

Monadic Chatは設定値にアクセスするための一貫したパターンを使用しています：

### 設定の優先順位

1. **CONFIG ハッシュ** - Dotenvを介して`~/monadic/config/env`ファイルから読み込まれます
2. **ENV 変数** - システム環境変数（フォールバック）
3. **デフォルト値** - どちらも設定されていない場合のハードコードされたデフォルト

### 標準アクセスパターン

```ruby
# コードベース全体で使用される標準パターン
value = CONFIG["KEY"] || ENV["KEY"] || "default_value"
```

### 使用例

```ruby
# APIキー
api_key = CONFIG["OPENAI_API_KEY"] || ENV["OPENAI_API_KEY"]

# モデル設定
default_model = CONFIG["OPENAI_DEFAULT_MODEL"] || ENV["OPENAI_DEFAULT_MODEL"] || "gpt-4.1"

# 機能フラグ
allow_jupyter = CONFIG["ALLOW_JUPYTER_IN_SERVER_MODE"] || ENV["ALLOW_JUPYTER_IN_SERVER_MODE"]

# 数値
max_tokens = CONFIG["AI_USER_MAX_TOKENS"]&.to_i || ENV["AI_USER_MAX_TOKENS"]&.to_i || 2000
```

### ベストプラクティス

- **ユーザー設定**: `~/monadic/config/env`ファイルに保存（CONFIGからアクセス）
- **デプロイメント時の上書き**: システム環境変数（ENV）を使用
- **開発時**: `rake server:debug`はCONFIGを上書きするENV値を設定
- **Docker**: コンテナ内の環境変数が優先されます

### 重要な注意点

- CONFIG値は起動時に`~/monadic/config/env`から読み込まれます
- ENVはCONFIG値を上書きできます（DockerとCI/CDに便利）
- 一部のレガシーコードはENVを最初にチェックする場合があります - これらは更新中です
- デバッグモード（`EXTRA_LOGGING`、`MONADIC_DEBUG`）は標準パターンに従います

## 完全な例

```ruby
app "ChatOpenAI" do
  description "OpenAIを使用した汎用チャットアプリケーション"
  icon "fa-comments"
  
  llm do
    provider "openai"
    model "gpt-4.1-mini"
    temperature 0.7
    max_tokens 4000
  end
  
  features do
    easy_submit true
    auto_speech false
    context_size 20
    monadic false
    # 注: 画像アップロードはビジョン機能を持つモデルで自動的に有効になります
    websearch true
  end
  
  tools do
    # 標準ツールのみを使用する場合でも空のブロックが必要
  end
  
  system_prompt <<~TEXT
    あなたは親切なAIアシスタントです。
  TEXT
end
```

## 関連項目

- [Monadic DSL](./monadic_dsl.md) - 完全なMDSL構文リファレンス
- [アプリの開発](./develop_apps.md) - アプリ作成ガイド
- [レシピファイルの例](./recipe-examples.md) - 実装例