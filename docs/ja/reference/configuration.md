# 設定リファレンス

このページでは、Monadic Chatのすべての設定オプションの包括的なリファレンスを提供します。設定は `~/monadic/config/env` ファイルまたはGUI設定パネルから行えます。

## 設定カテゴリー

- [設定優先度](#設定優先度)
- [APIキー](#apiキー)
- [モデル設定](#モデル設定)
- [システム設定](#システム設定)
- [音声設定](#音声設定)
- [ヘルプシステム設定](#ヘルプシステム設定)
- [開発設定](#開発設定)
- [コンテナ設定](#コンテナ設定)
- [インストールオプション](#インストールオプション)
- [PDF処理設定](#pdf処理設定)

## 設定優先度

Monadic Chatは設定値に対して以下の優先順位を使用します（高い順）：

1. **環境変数** (`~/monadic/config/env`)
   - ユーザー定義の設定が最優先
   - 他のすべての設定ソースを上書き

2. **プロバイダーデフォルト** (`model_spec.js`内の`providerDefaults`)
   - 単一の信頼できるソース(SSOT)として定義されたプロバイダー固有のデフォルトモデル
   - 環境変数が設定されていない場合に適用

3. **ハードコードされたデフォルト**
   - コード内の組み込みフォールバック値
   - ENVとproviderDefaultsのどちらも値を提供しない場合の最終手段

### 例

OpenAIのデフォルトモデルの場合：
- `~/monadic/config/env`に`OPENAI_DEFAULT_MODEL=<model-id>`が設定されている場合、それが使用されます
- そうでない場合、`model_spec.js`の`providerDefaults`の値が使用されます
- どちらも存在しない場合、アプリケーション内のハードコードされたデフォルトが適用されます

> **Note**: 現在のデフォルト値は`docker/services/ruby/public/js/monadic/model_spec.js`の`providerDefaults`を参照してください。モデル名は頻繁に更新されるため、最新の値は実装ファイルで確認することを推奨します。

## APIキー

| 変数名 | 説明 | 必須 | 例 |
|--------|------|------|-----|
| `OPENAI_API_KEY` | GPTモデル用のOpenAI APIキー | はい（OpenAIアプリ使用時） | `sk-...` |
| `ANTHROPIC_API_KEY` | Claudeモデル用のAnthropic APIキー | はい（Claudeアプリ使用時） | `sk-ant-...` |
| `GEMINI_API_KEY` | Geminiモデル用のGoogle APIキー | はい（Geminiアプリ使用時） | `AIza...` |
| `MISTRAL_API_KEY` | Mistral AI APIキー | はい（Mistralアプリ使用時） | `...` |
| `COHERE_API_KEY` | Cohere APIキー | はい（Cohereアプリ使用時） | `...` |
| `DEEPSEEK_API_KEY` | DeepSeek APIキー | はい（DeepSeekアプリ使用時） | `...` |
| `XAI_API_KEY` | Grokモデル用のxAI APIキー | はい（Grokアプリ使用時） | `xai-...` |
| `ELEVENLABS_API_KEY` | TTSおよびScribe音声認識用のElevenLabs APIキー | はい（ElevenLabs音声使用時） | `...` |
| `TAVILY_API_KEY` | ウェブ検索用のTavily APIキー（Mistral、Cohere、DeepSeek、Ollamaのウェブ検索に必要） | いいえ | `tvly-...` |

## モデル設定

> **Note**: デフォルト値は`docker/services/ruby/public/js/monadic/model_spec.js`の`providerDefaults`を参照してください。以下の表は変数名と用途の説明のみを記載しています。

| 変数名 | 説明 | 使用例 |
|--------|------|--------|
| `OPENAI_DEFAULT_MODEL` | OpenAIアプリのデフォルトモデル | `OPENAI_DEFAULT_MODEL=<model-id>` |
| `ANTHROPIC_DEFAULT_MODEL` | Claudeアプリのデフォルトモデル | `ANTHROPIC_DEFAULT_MODEL=<model-id>` |
| `TOKEN_COUNT_SOURCE` | トークンカウントのソースポリシー | `TOKEN_COUNT_SOURCE=provider_only`（オプション: `provider_only`, `hybrid`） |
| `GEMINI_DEFAULT_MODEL` | Geminiアプリのデフォルトモデル | `GEMINI_DEFAULT_MODEL=<model-id>` |
| `MISTRAL_DEFAULT_MODEL` | Mistralアプリのデフォルトモデル | `MISTRAL_DEFAULT_MODEL=<model-id>` |
| `COHERE_DEFAULT_MODEL` | Cohereアプリのデフォルトモデル | `COHERE_DEFAULT_MODEL=<model-id>` |
| `DEEPSEEK_DEFAULT_MODEL` | DeepSeekアプリのデフォルトモデル | `DEEPSEEK_DEFAULT_MODEL=<model-id>` |
| `GROK_DEFAULT_MODEL` | Grokアプリのデフォルトモデル | `GROK_DEFAULT_MODEL=<model-id>` |
| `OLLAMA_DEFAULT_MODEL` | Ollamaアプリのデフォルトモデル | `OLLAMA_DEFAULT_MODEL=<model-id>` |

### UIでのモデル選択

**Model** ドロップダウンには、選択中のアプリに適した推奨モデルのキュレーションリストが表示されます。このリストはアプリのMDSL定義またはプロバイダのデフォルトモデルセットから取得されます。

プロバイダの全モデルを表示するには、Modelラベル横の **全て** スイッチを切り替えてください。「全て」モードでも、現在のアプリと互換性のないモデル（ツールが必要なアプリでツール非対応のモデルなど）は自動的に除外されます。トグルの設定はブラウザのクッキーを通じてセッション間で保持されます。

## システム設定

| 変数名 | 説明 | デフォルト | 範囲/オプション |
|--------|------|------------|-----------------|
| `MAX_STORED_MESSAGES` | セッション復元のためにlocalStorageに保存される最大メッセージ数 | `1000` | 50-1000（context sizeが有効な場合、その値を超えることはできません） |
| `ROUGE_THEME` | シンタックスハイライトのテーマ | `github:light` | [利用可能なテーマ](../basic-usage/syntax-highlighting.md)を参照 |

> **注意**: `MAX_STORED_MESSAGES`は、ブラウザセッション間で永続化される会話メッセージの数を決定します。Web UIでcontext size設定が有効になっている場合、実際の上限は`MAX_STORED_MESSAGES`と設定されたcontext sizeの値のうち、小さい方になります。

## 音声設定

| 変数名 | 説明 | デフォルト | 範囲/オプション |
|--------|------|------------|----------------|
| `TTS_DICT_PATH` | TTS発音辞書CSVのパス。Electronの設定パネル（「TTS辞書ファイルパス」）で設定すると、ファイルが`~/monadic/config/TTS_DICT.csv`にコピーされ、サーバーがこれを読み込みます | （オプション） | ファイルパス |
| `TTS_DICT_DATA` | インラインTTS発音データ（レガシー。辞書ファイルがない場合のみ使用） | （オプション） | CSV形式 |

> **Note**: 音声認識（STT）モデルは環境変数では設定しません。Web UIの**Speech**パネルで選択してください。選択内容はブラウザのクッキーに保存されます。

## ヘルプシステム設定

| 変数名 | 説明 | デフォルト | 範囲 |
|--------|------|------------|------|
| `HELP_CHUNK_SIZE` | ドキュメントチャンクあたりの文字数 (ビルド時) | `3000` | 1000-8000 |
| `HELP_OVERLAP_SIZE` | チャンク間の文字重複数 (ビルド時) | `500` | 100-2000 |
| `HELP_CHUNKS_PER_RESULT` | 検索ごとに返されるチャンク数 | `3` | 1-10 |

## 開発設定

| 変数名 | 説明 | デフォルト | オプション |
|--------|------|------------|-----------|
| `DISTRIBUTED_MODE` | マルチユーザーサーバーモードを有効化 | `off` | `off`, `server` |
| `SESSION_SECRET` | セッション管理用の秘密鍵 | （自動生成） | 任意の文字列 |
| `MCP_SERVER_ENABLED` | Model Context Protocolサーバーを有効化 | `false` | `true`, `false` |
| `MCP_SERVER_PORT` | Model Context Protocolサーバーのポート | `3100` | 空いている任意のポート |
| `ALLOW_JUPYTER_IN_SERVER_MODE` | サーバーモードでJupyterを有効化 | `false` | `true`, `false` |
| `EXTRA_LOGGING` | 詳細なロギングを有効化 | `false` | `true`, `false` |

### アプリケーションモード

Monadic Chatは、ネットワークアクセスを制御する2つのアプリケーションモードをサポートしています：

**Standaloneモード**（デフォルト: `DISTRIBUTED_MODE=off` または未設定）
- サーバーは`127.0.0.1`（ローカルホストのみ）にバインド
- ローカルマシンからのみアクセス可能
- JupyterLab環境が有効
- シングルユーザーのローカル開発に推奨

**Server Mode** (`DISTRIBUTED_MODE=server`)
- サーバーは`0.0.0.0`（すべてのネットワークインターフェース）にバインド
- ネットワーク上の任意のデバイスからローカルIPアドレス経由でアクセス可能（例: `http://192.168.1.10:4567`）
- 接続された各デバイスは独立したセッションを持ち、会話状態はブラウザセッションごとに個別に保存（デバイス間・ブラウザ間で共有されない）
- セキュリティのため、デフォルトでJupyterLabは無効（`ALLOW_JUPYTER_IN_SERVER_MODE=true`で有効化可能）
- セッション分離の詳細は[高度な設定](/ja/advanced-topics/advanced-configuration.md)を参照

## コンテナ設定

| 変数名 | 説明 | デフォルト | 備考 |
|--------|------|------------|------|
| `QDRANT_URL` | Qdrant のフル URL | `http://qdrant_service:6333`（コンテナ内）/ `http://localhost:6333`（dev） | 上書きする場合のみ設定 |
| `EMBEDDINGS_URL` | Embeddings サービスのフル URL | `http://embeddings_service:8000`（コンテナ内）/ `http://localhost:8002`（dev） | 上書きする場合のみ設定 |
| `EMBEDDINGS_DEV_PORT` | dev モード時の Embeddings ホストポート | `8002` | `compose.dev.yml` 経由で公開 |
| `QDRANT_DEV_PORT` | dev モード時の Qdrant ホストポート | `6333` | `compose.dev.yml` 経由で公開 |
| `START_HEALTH_TRIES` | 起動時ヘルスプローブの試行回数 | `20` | [高度な設定](/ja/advanced-topics/advanced-configuration.md#startup-health-tuning)を参照 |
| `START_HEALTH_INTERVAL` | 起動時ヘルスプローブの試行間隔（秒） | `2` | [高度な設定](/ja/advanced-topics/advanced-configuration.md#startup-health-tuning)を参照 |
| `FORCE_RUBY_REBUILD_NO_CACHE` | RubyコンテナのリビルドをDockerキャッシュなしで強制実行 | `false` | [高度な設定](/ja/advanced-topics/advanced-configuration.md#ruby-rebuild)を参照 |

## インストールオプション

これらのオプションはPythonコンテナにインストールされる追加パッケージを制御します。変更には**アクション → Pythonコンテナビルド**からのコンテナ再ビルドが必要です。

| 変数名 | 説明 | 必須となるアプリ | デフォルト |
|--------|------|-----------------|------------|
| `INSTALL_LATEX` | LaTeXツールチェーン（TeX Live、dvisvgm、CJKパッケージ） | Syntax Tree、Concept Visualizer | `false` |
| `PYOPT_NLTK` | 自然言語処理ツールキット | NLPアプリケーション | `false` |
| `PYOPT_SPACY` | spaCy NLPライブラリ（v3.7.5） | 高度なNLPタスク | `false` |
| `PYOPT_GENSIM` | トピックモデリングライブラリ | テキスト分析 | `false` |
| `PYOPT_LIBROSA` | オーディオ分析ライブラリ | 音声処理 | `false` |
| `PYOPT_MEDIAPIPE` | コンピュータビジョンフレームワーク | ビジョンアプリケーション | `false` |
| `PYOPT_TRANSFORMERS` | Hugging Face Transformers | 深層学習NLP | `false` |
| `IMGOPT_IMAGEMAGICK` | ImageMagick画像処理 | 高度な画像操作 | `false` |

### インストールオプションの設定方法

**GUI経由（推奨）：**
1. Electronアプリメニュー：**アクション → インストールオプション**
2. 必要なオプションを切り替え
3. **保存**をクリック
4. メニュー：**アクション → Pythonコンテナビルド**

**設定ファイル経由：**
```bash
# ~/monadic/config/env
INSTALL_LATEX=true
PYOPT_NLTK=true
PYOPT_LIBROSA=true
```

### スマートビルドキャッシング

ビルドシステムは自動的にリビルド速度を最適化します：

- **オプション未変更**：キャッシュを使用した高速リビルド（約1〜2分）
- **オプション変更**：`--no-cache`を使用した完全リビルド（約15〜30分）
- **自動再起動**：ビルド成功後、コンテナが自動的に再起動

以前のビルドオプションは`~/monadic/log/python_build_options.txt`で追跡されます。システムは現在のオプションと以前のビルドを比較し、信頼性を確保しながら速度を最大化するため、必要な場合のみ`--no-cache`を使用します。

### 重要な注意事項

- LaTeXパッケージには完全なTeX Live、CJK言語サポート、日本語/中国語/韓国語テキストレンダリング用のdvisvgmが含まれます
- NLTKとspaCyオプションはパッケージのみをインストールします。データセット/モデルは`pysetup.sh`経由で別途ダウンロードする必要があります
- 変更はリビルド後すぐに有効になります。手動でコンテナを再起動する必要はありません
- ビルド失敗時は現在のイメージが保持されます（アトミック更新）

## PDF処理設定

| 変数名 | 説明 | デフォルト | 範囲 |
|--------|------|------------|------|
| `PDF_RAG_TOKENS` | PDFチャンクあたりのトークン数 | `4000` | 500-8000 |
| `PDF_RAG_OVERLAP_LINES` | PDFチャンク間の行重複数 | `4` | 0-20 |

## 設定例

### 基本設定
```bash
# ~/monadic/config/env

# 必須APIキー
OPENAI_API_KEY=sk-...
ANTHROPIC_API_KEY=sk-ant-...

# モデル設定
OPENAI_DEFAULT_MODEL=<model-id>

# UI設定
ROUGE_THEME=github:light
```

### 高度な設定
```bash
# ウェブ検索
TAVILY_API_KEY=tvly-...

# PDF処理
PDF_RAG_TOKENS=6000
PDF_RAG_OVERLAP_LINES=6

# 開発
DISTRIBUTED_MODE=server
MCP_SERVER_ENABLED=true
```

## 注意事項

- ブール値は `true`/`false` または `1`/`0` で設定できます
- ファイルパスは絶対パスで指定してください
- 一部の設定はコンテナの再起動が必要です
- セキュリティのため、APIキーはGUIには表示されません
