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

2. **システムデフォルト** (`config/system_defaults.json`)
   - プロバイダー固有のデフォルトモデルと設定
   - 環境変数が設定されていない場合に適用

3. **ハードコードされたデフォルト**
   - コード内の組み込みフォールバック値
   - ENVとsystem_defaultsのどちらも値を提供しない場合の最終手段

### 例

OpenAIのデフォルトモデルの場合：
- `~/monadic/config/env`に`OPENAI_DEFAULT_MODEL=<model-id>`が設定されている場合、それが使用されます
- そうでない場合、`system_defaults.json`の値が使用されます
- どちらも存在しない場合、アプリケーション内のハードコードされたデフォルトが適用されます

> **Note**: 現在のデフォルト値は`docker/services/ruby/config/system_defaults.json`を参照してください。モデル名は頻繁に更新されるため、最新の値は実装ファイルで確認することを推奨します。

## APIキー

| 変数名 | 説明 | 必須 | 例 |
|--------|------|------|-----|
| `OPENAI_API_KEY` | GPTモデル用のOpenAI APIキー | はい（OpenAIアプリ使用時） | `sk-...` |
| `ANTHROPIC_API_KEY` | Claudeモデル用のAnthropic APIキー | はい（Claudeアプリ使用時） | `sk-ant-...` |
| `GEMINI_API_KEY` | Geminiモデル用のGoogle APIキー | はい（Geminiアプリ使用時） | `AIza...` |
| `MISTRAL_API_KEY` | Mistral AI APIキー | はい（Mistralアプリ使用時） | `...` |
| `COHERE_API_KEY` | Cohere APIキー | はい（Cohereアプリ使用時） | `...` |
| `DEEPSEEK_API_KEY` | DeepSeek APIキー | はい（DeepSeekアプリ使用時） | `...` |
| `PERPLEXITY_API_KEY` | Perplexity APIキー | はい（Perplexityアプリ使用時） | `pplx-...` |
| `XAI_API_KEY` | Grokモデル用のxAI APIキー | はい（Grokアプリ使用時） | `xai-...` |
| `TAVILY_API_KEY` | ウェブ検索用のTavily APIキー | いいえ | `tvly-...` |

## モデル設定

> **Note**: デフォルト値は`docker/services/ruby/config/system_defaults.json`を参照してください。以下の表は変数名と用途の説明のみを記載しています。

| 変数名 | 説明 | 使用例 |
|--------|------|--------|
| `OPENAI_DEFAULT_MODEL` | OpenAIアプリのデフォルトモデル | `OPENAI_DEFAULT_MODEL=<model-id>` |
| `ANTHROPIC_DEFAULT_MODEL` | Claudeアプリのデフォルトモデル | `ANTHROPIC_DEFAULT_MODEL=<model-id>` |
| `GEMINI_DEFAULT_MODEL` | Geminiアプリのデフォルトモデル | `GEMINI_DEFAULT_MODEL=<model-id>` |
| `MISTRAL_DEFAULT_MODEL` | Mistralアプリのデフォルトモデル | `MISTRAL_DEFAULT_MODEL=<model-id>` |
| `COHERE_DEFAULT_MODEL` | Cohereアプリのデフォルトモデル | `COHERE_DEFAULT_MODEL=<model-id>` |
| `DEEPSEEK_DEFAULT_MODEL` | DeepSeekアプリのデフォルトモデル | `DEEPSEEK_DEFAULT_MODEL=<model-id>` |
| `PERPLEXITY_DEFAULT_MODEL` | Perplexityアプリのデフォルトモデル | `PERPLEXITY_DEFAULT_MODEL=<model-id>` |
| `GROK_DEFAULT_MODEL` | Grokアプリのデフォルトモデル | `GROK_DEFAULT_MODEL=<model-id>` |

## システム設定

| 変数名 | 説明 | デフォルト | 範囲/オプション |
|--------|------|------------|-----------------|
| `FONT_SIZE` | インターフェースの基本フォントサイズ | `16` | 10-24 |
| `AUTONOMOUS_ITERATIONS` | 自律モードの反復回数 | `2` | 1-10 |
| `MAX_CHAR_COUNT` | メッセージの最大文字数 | `200000` | 1000-500000 |
| `PDF_BOLD_FONT_PATH` | PDF生成用の太字フォントパス | （オプション） | ファイルパス |
| `PDF_STANDARD_FONT_PATH` | PDF生成用の標準フォントパス | （オプション） | ファイルパス |
| `ROUGE_THEME` | シンタックスハイライトのテーマ | `pastie:light` | [利用可能なテーマ](../basic-usage/syntax-highlighting.md)を参照 |

## 音声設定

| 変数名 | 説明 | デフォルト | 範囲/オプション |
|--------|------|------------|----------------|
| `STT_MODEL` | 音声認識モデル | system_defaults.json参照 | 利用可能なモデルはプロバイダーのドキュメント参照 |
| `TTS_DICT_PATH` | TTS発音辞書のパス | （オプション） | ファイルパス |
| `TTS_DICT_DATA` | インラインTTS発音データ | （オプション） | CSV形式 |
| `AUTO_TTS_MIN_LENGTH` | リアルタイムモードでTTS生成前の最小テキスト長 | `50` | 20-200文字 |

## ヘルプシステム設定

| 変数名 | 説明 | デフォルト | 範囲 |
|--------|------|------------|------|
| `HELP_CHUNK_SIZE` | ドキュメントチャンクあたりの文字数 | `3000` | 1000-8000 |
| `HELP_OVERLAP_SIZE` | チャンク間の文字重複数 | `500` | 100-2000 |
| `HELP_EMBEDDINGS_BATCH_SIZE` | エンベディングAPIコールのバッチサイズ | `50` | 1-100 |
| `HELP_CHUNKS_PER_RESULT` | 検索ごとに返されるチャンク数 | `3` | 1-10 |

## 開発設定

| 変数名 | 説明 | デフォルト | オプション |
|--------|------|------------|-----------|
| `DISTRIBUTED_MODE` | マルチユーザーサーバーモードを有効化 | `false` | `true`, `false` |
| `SESSION_SECRET` | セッション管理用の秘密鍵 | （自動生成） | 任意の文字列 |
| `MCP_SERVER_ENABLED` | Model Context Protocolサーバーを有効化 | `false` | `true`, `false` |
| `PYTHON_PORT` | Pythonコンテナサービスのポート | `5070` | 1024-65535 |
| `ALLOW_JUPYTER_IN_SERVER_MODE` | サーバーモードでJupyterを有効化 | `false` | `true`, `false` |

## コンテナ設定

| 変数名 | 説明 | デフォルト | 備考 |
|--------|------|------------|------|
| `OLLAMA_AVAILABLE` | Ollamaコンテナの利用可否 | （自動検出） | システムが設定 |
| `POSTGRES_HOST` | PostgreSQLホスト | `monadic-chat-pgvector-container` | Dockerネットワーク用 |
| `POSTGRES_PORT` | PostgreSQLポート | `5432` | 標準PostgreSQLポート |
| `POSTGRES_USER` | PostgreSQLユーザー | `postgres` | データベースユーザー |
| `POSTGRES_PASSWORD` | PostgreSQLパスワード | `postgres` | データベースパスワード |

## インストールオプション

これらのオプションはPythonコンテナにインストールされる追加パッケージを制御します。変更には**アクション → Pythonコンテナビルド**からのコンテナ再ビルドが必要です。

| 変数名 | 説明 | 必須となるアプリ | デフォルト |
|--------|------|-----------------|------------|
| `INSTALL_LATEX` | LaTeXツールチェーン（TeX Live、dvisvgm、CJKパッケージ） | Syntax Tree、Concept Visualizer | `false` |
| `PYOPT_NLTK` | 自然言語処理ツールキット | NLPアプリケーション | `false` |
| `PYOPT_SPACY` | spaCy NLPライブラリ（v3.7.5） | 高度なNLPタスク | `false` |
| `PYOPT_SCIKIT` | scikit-learn機械学習ライブラリ | 機械学習アプリケーション | `false` |
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
FONT_SIZE=18
ROUGE_THEME=github
```

### 高度な設定
```bash
# ウェブ検索と音声
TAVILY_API_KEY=tvly-...
STT_MODEL=whisper-1

# PDF処理
PDF_RAG_TOKENS=6000
PDF_RAG_OVERLAP_LINES=6

# 開発
DISTRIBUTED_MODE=true
MCP_SERVER_ENABLED=true
```

## 注意事項

- ブール値は `true`/`false` または `1`/`0` で設定できます
- ファイルパスは絶対パスで指定してください
- 一部の設定はコンテナの再起動が必要です
- セキュリティのため、APIキーはGUIには表示されません
