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
- `app "AppName"` - アプリ識別子。Rubyクラス名と正確に一致する必要があります（例：`app "ChatOpenAI"`には`class ChatOpenAI`が必要）
- `description` - アプリケーションの目的の簡潔な説明
- `icon` - アイコン識別子（Font Awesomeクラスまたは組み込みアイコン名）
- `system_prompt` - AIモデルへのシステム指示

### LLM設定
`llm`ブロックは必須で、以下を含みます：
- `provider` - AIプロバイダー（openai、claude、geminiなど）
- `model` - 使用する特定のモデル

## オプション設定

### LLMブロックのオプション
- `temperature` - 応答のランダム性を制御。範囲と利用可否はプロバイダーとモデルに依存。一部のモデル（OpenAI o1/o3、Gemini 2.5思考型モデルなど）はtemperature調整をサポートしません
- `max_tokens` - レスポンスの最大トークン数（利用可否と上限はモデルにより異なる）
- `presence_penalty` - 繰り返しトピックのペナルティ。一部のOpenAIおよびMistralモデルでサポート
- `frequency_penalty` - 繰り返し単語のペナルティ。一部のOpenAIおよびMistralモデルでサポート

### Featuresブロック
featuresブロック内のすべての設定はオプションです：

#### 表示とインタラクション
- `display_name` - UIに表示される名前（デフォルトはアプリ名）
- `group` - UIでアプリを整理するためのメニューグループ名。デフォルトでは、アプリはプロバイダーごとに自動的にグループ化されます（例：「OpenAI」、「Anthropic」）。カスタムグループを作成するために上書きできますが、デフォルトのプロバイダーベースのグループ化を維持することを推奨します
- `disabled` - trueの場合、メニューからアプリを非表示
- `easy_submit` - Enterキーのみでメッセージ送信
- `auto_speech` - AI応答を音声として自動再生
- `initiate_from_assistant` - AIメッセージで会話を開始

#### コンテンツ機能
- `pdf_vector_storage` - RAG（検索拡張生成）のためのPDFデータベース機能を有効化。UIにPDFインポートボタンとデータベースパネルを表示
- `file` - テキストファイルアップロードを有効化
- `websearch` - ウェブ検索機能を有効化
- `image_generation` - AI画像生成機能を有効化。以下の値を受け付けます：
  - `true` - 完全な画像生成機能（作成、編集、バリエーション）
  - `"upload_only"` - 画像アップロードのみ（生成・編集なし）
  - `false` - 無効（デフォルト）
- `mermaid` - Mermaidダイアグラムレンダリングを有効化
- `abc` - ABC音楽記譜法を有効化
- `sourcecode` - シンタックスハイライトを有効化
- `mathjax` - LaTeX数式レンダリングを有効化

#### コンテキスト管理
- `context_size` - 含める過去のメッセージ数
- `monadic` - JSONベースの状態管理を有効化（複数プロバイダーで利用可能、機能は異なる）
- `toggle` - 折りたたみ可能セクションを有効化（Claude/Gemini/Mistral/Cohere）
- `prompt_suffix` - すべてのユーザーメッセージに追加されるテキスト

?> **重要**: `monadic`と`toggle`を両方有効にしないでください - これらは相互排他的な表示モードです。

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
- `response_format` - 構造化出力形式を指定（OpenAI）
- `reasoning_effort` - 推論モデル用："low"（デフォルト）、"medium"、"high"
- `models` - 利用可能なモデルリストを上書き
- `jupyter` - Jupyterノートブックアクセスを有効化（Serverモードでは`ALLOW_JUPYTER_IN_SERVER_MODE=true`を設定しない限り無効）

!> **重要**: `jupyter`機能はUIの機能を有効にするだけです。実際のJupyter機能を使用するには、アプリで対応するツール定義（`run_jupyter`、`create_jupyter_notebook`など）を実装する必要があります。例については、Jupyter Notebookアプリの実装を参照してください。

## システムレベル設定

これらはMDSLファイルではなく、Monadic Chatの設定パネルで設定されます：

- 各プロバイダーのAPIキー（OpenAI、Claude、Geminiなど）
- Tavilyウェブ検索用APIキー
- シンタックスハイライトテーマ
- 音声認識モデル選択

設定はアプリケーション起動時に読み込まれ、セッション間で保持されます。


## 完全な例

```ruby
app "ChatOpenAI" do
  description "OpenAIを使用した汎用チャットアプリケーション"
  icon "fa-comments"

  llm do
    provider "openai"
    model ["<model-1>", "<model-2>"]  # ユーザー選択用のモデルIDの配列
    reasoning_effort "minimal"
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

