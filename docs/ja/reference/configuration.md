# 設定リファレンス

このページでは、Monadic Chatのすべての設定オプションの包括的なリファレンスを提供します。設定は `~/monadic/config/env` ファイルまたはGUI設定パネルから行えます。

## 設定カテゴリー

- [APIキー](#apiキー)
- [モデル設定](#モデル設定)
- [システム設定](#システム設定)
- [音声設定](#音声設定)
- [ヘルプシステム設定](#ヘルプシステム設定)
- [開発設定](#開発設定)
- [コンテナ設定](#コンテナ設定)

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

| 変数名 | 説明 | デフォルト | 例 |
|--------|------|------------|-----|
| `OPENAI_DEFAULT_MODEL` | OpenAIアプリのデフォルトモデル | `gpt-4.1` | `gpt-4.1-mini` |
| `ANTHROPIC_DEFAULT_MODEL` | Claudeアプリのデフォルトモデル | `claude-sonnet-4-20250514` | `claude-3.5-haiku-20241022` |
| `GEMINI_DEFAULT_MODEL` | Geminiアプリのデフォルトモデル | `gemini-2.5-flash` | `gemini-1.5-pro` |
| `MISTRAL_DEFAULT_MODEL` | Mistralアプリのデフォルトモデル | `mistral-large-latest` | `magistral-medium-2509` |
| `COHERE_DEFAULT_MODEL` | Cohereアプリのデフォルトモデル | `command-a-03-2025` | `command-a-reasoning-08-2025` |
| `DEEPSEEK_DEFAULT_MODEL` | DeepSeekアプリのデフォルトモデル | `deepseek-chat` | `deepseek-coder` |
| `PERPLEXITY_DEFAULT_MODEL` | Perplexityアプリのデフォルトモデル | `sonar-reasoning-pro` | `sonar-reasoning` |
| `XAI_DEFAULT_MODEL` | Grokアプリのデフォルトモデル | `grok-4-fast-reasoning` | `grok-4-fast-non-reasoning` |

## システム設定

| 変数名 | 説明 | デフォルト | 範囲/オプション |
|--------|------|------------|-----------------|
| `FONT_SIZE` | インターフェースの基本フォントサイズ | `16` | 10-24 |
| `AUTONOMOUS_ITERATIONS` | 自律モードの反復回数 | `2` | 1-10 |
| `MAX_CHAR_COUNT` | メッセージの最大文字数 | `200000` | 1000-500000 |
| `PDF_BOLD_FONT_PATH` | PDF生成用の太字フォントパス | （オプション） | ファイルパス |
| `PDF_STANDARD_FONT_PATH` | PDF生成用の標準フォントパス | （オプション） | ファイルパス |
| `ROUGE_THEME` | シンタックスハイライトのテーマ | `monokai.sublime` | [利用可能なテーマ](../basic-usage/syntax-highlighting.md)を参照 |

## 音声設定

| 変数名 | 説明 | デフォルト | オプション |
|--------|------|------------|-----------|
| `STT_MODEL` | 音声認識モデル | `gpt-4o-transcribe` | `gpt-4o-transcribe`, `gpt-4o-mini-transcribe`, `whisper-1` |
| `TTS_DICT_PATH` | TTS発音辞書のパス | （オプション） | ファイルパス |
| `TTS_DICT_DATA` | インラインTTS発音データ | （オプション） | CSV形式 |

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
OPENAI_DEFAULT_MODEL=gpt-4.1

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
