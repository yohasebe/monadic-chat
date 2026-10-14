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
- `app "AppName"` - アプリの名前。作られる Ruby のクラスの名前にもなります（例：`app "ChatOpenAI"`）
- `description` - アプリケーションの目的の簡潔な説明
- `icon` - アイコン識別子（Font Awesome のクラスまたはアイコンの名前）
- `system_prompt` - AIモデルへのシステム指示

`description`、`icon`、`system_prompt` がない場合も、アプリは既定の値で読み込まれ、アプリの説明に警告が表示されます。

### アプリレベルの任意設定
- `display_name` - UIに表示される名前（デフォルトはアプリ名）。`features` の中ではなく、`description` や `icon` と同じアプリレベルに書きます

### LLM設定
`llm`ブロックには、以下を書きます：
- `provider` - AIプロバイダー（`openai`、`anthropic`、`gemini`、`mistral`、`cohere`、`deepseek`、`xai`、`ollama`）
- `model` - モデル。メニューで選ばせるときはモデルの配列。省くと、プロバイダーの既定のモデルが使われます

## オプション設定

### LLMブロックのオプション
- `temperature` - 応答のランダム性を制御（0.0〜2.0、既定 0.7）。モデルが受け付ける範囲はプロバイダーとモデルによって違い、推論のモデルの中には受け付けないものもあります
- `max_tokens` - レスポンスの最大トークン数（利用可否と上限はモデルにより異なる）
- `presence_penalty` - 繰り返しトピックのペナルティ。一部のOpenAIおよびMistralモデルでサポート
- `frequency_penalty` - 繰り返し単語のペナルティ。一部のOpenAIおよびMistralモデルでサポート

### Featuresブロック
featuresブロック内のすべての設定はオプションです：

#### 表示とインタラクション
- `group` - UIでアプリを整理するためのメニューグループ名。既定では、アプリはプロバイダーごとにまとめられます（例：「OpenAI」、「Anthropic」）
- `disabled` - trueの場合、メニューからアプリを非表示
- `easy_submit` - Enterキーのみでメッセージ送信
- `auto_speech` - AI応答を音声として自動再生
- `initiate_from_assistant` - AIメッセージで会話を開始

#### コンテンツ機能
- `pdf_vector_storage` - RAG（検索拡張生成）のためのPDFデータベース機能を有効化。UIにPDFインポートボタンとデータベースパネルを表示
- `websearch` - ウェブ検索機能を有効化
- `image_generation` - AI画像生成機能を有効化。以下の値を受け付けます：
  - `true` - 画像の生成と編集
  - `"upload_only"` - 画像アップロードのみ（生成・編集なし）
  - `false` - 無効（デフォルト）
- `mermaid` - Mermaidダイアグラムレンダリングを有効化
- `abc` - ABC音楽記譜法を有効化
- `math` - LaTeX数式レンダリングを有効化

#### speech-to-speech
テキスト入力パネルの代わりにマイク音声をプロバイダの realtime API へ直接ストリーミングする Live Conversation 系アプリ向けの設定です:
- `speech_to_speech` - このアプリを speech-to-speech アプリにする（テキスト入力が開始/終了ボタンに置き換わる）
- `sts_input_rate` - マイクのサンプルレート（Hz、既定 24000。Gemini Live は 16000）
- `sts_vad_threshold` - 音声区間検出の感度（0.0〜1.0、値が大きいほど環境音に反応しにくい）
- `sts_vad_prefix_ms` - 発話開始前に保持する音声の長さ（ミリ秒）
- `sts_vad_silence_ms` - ターンの終わりと判定する無音の長さ（ミリ秒）
- `sts_vad_type` - ターン判定方式: `server_vad`（既定・無音ベース）または `semantic_vad`（意味の完結を待つ。OpenAI のみ）
- `sts_vad_eagerness` - `semantic_vad` がターンを閉じる速さ: `low`、`medium`、`high`、`auto`（OpenAI のみ。それ以外では無視）
- `sts_idle_stop_seconds` - 無操作がこの秒数続いたらセッションを自動停止（既定 180、0 で無効）

`sts_vad_*` は省略するとプロバイダ既定値が使われます。またすべてのプロバイダがすべてのキーを解釈するわけではありません（xAI は `sts_vad_prefix_ms` を無視します）。OpenAI 変種の Live Conversation では `sts_vad_type` / `sts_vad_eagerness` をユーザーがターン判定セレクタから選ぶこともでき、選択した値は次のセッションで MDSL の既定より優先されます。

#### コンテキスト管理
- `context_size` - モデルに送る直近のメッセージの数。Web の画面の **Max Context Size** の欄の値にもなります
- `monadic` - Session State と Session Context を有効化。[Monadic モード](./monadic-mode.md)を参照
- `toggle` - 応答の中の `<div class='toggle'>` のブロックを、折りたためる節として表示
- `prompt_suffix` - すべてのユーザーメッセージに追加されるテキスト

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
- `response_format` - 構造化出力形式を指定（OpenAI。Ollama では、Ollama の `format` パラメーターに変換されます）
- `reasoning_effort` - サポートされているモデルの推論強度を制御。利用可能な値はモデルによって異なります（例：一部のモデルでは "low", "high"）
- `jupyter` - Jupyterノートブックアクセスを有効化
- `reachable_skills` - 会話の流れに応じてアプリがオンデマンドで獲得できるツールグループを宣言（`tools`ブロックの外、アプリレベルに記述）。`reachable_skills :safe`は読み取り専用の安全なグループ一式に展開されます。[ツールグループ](./tool-groups.md)を参照
- `compaction` - サーバーサイドの会話コンパクション（対応するAPIを持つプロバイダーで有効）を制御（アプリレベルに記述）。OpenAIアプリではこのディレクティブがなくてもデフォルトのしきい値で有効です。`compaction false`でオプトアウト、`compaction do ... end`ブロック内の`compact_threshold`でトリガーしきい値をカスタマイズできます

!> **重要**: `jupyter`機能はUIの機能を有効にするだけです。実際のJupyter機能を使用するには、アプリで対応するツール定義（`:jupyter_operations` のグループの `create_jupyter_notebook`、`run_jupyter_cells` など）を実装する必要があります。例については、Jupyter Notebookアプリの実装を参照してください。

## システムレベル設定

これらは MDSL ファイルではなく、**Settings** ウィンドウ（**Open → Settings**）で設定します。項目は General、System、API Keys、Voice & Audio、Services、Install Options、Actions、About です。設定できるものの例：

- 各プロバイダー、ElevenLabs、Tavily の API キー
- UI の言語、Browser Mode、Launch at Login、Menu Bar Mode
- Extra Logging
- TTS の辞書のファイルと、Auto Speech の大きさの上限
- MCP サーバーとそのポート
- [Install Options](./advanced-configuration.md#install-options)（Privacy Filter の言語、Knowledge Base Quality Pack を含む）

設定は `~/monadic/config/env` に保存され、セッションをまたいで保たれます。

音声認識（STT）のモデルは、Settings ウィンドウや MDSL ファイルではなく、Web の画面の **Speech** パネルで選びます。選んだものはブラウザーの Cookie に保存されます。

## 完全な例

```ruby
app "ChatOpenAI" do
  description "OpenAIを使用した汎用チャットアプリケーション"
  icon "fa-solid fa-comments"

  llm do
    provider "openai"
    model ["<model-1>", "<model-2>"]  # ユーザー選択用のモデルIDの配列
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
  
  system_prompt <<~TEXT
    あなたは親切なAIアシスタントです。
  TEXT
end
```

## 関連項目

- [Monadic DSL](./monadic_dsl.md) - 完全なMDSL構文リファレンス
- [アプリの開発](./develop_apps.md) - アプリ作成ガイド
- [レシピファイルの例](./recipe-examples.md) - 実装例

