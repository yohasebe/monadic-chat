# 設定リファレンス

このページでは、`~/monadic/config/env` の設定を一覧にします。多くは **Settings** ウィンドウ（**Open → Settings**）にもあり、同じファイルに書かれます。アプリはこのファイルを書くたびに、自分のユーザーアカウントだけが読み書きできる権限にします（Windows では WSL の中で）。手で編集したファイルは、アプリが書くまで元の権限のままです。

## 設定カテゴリー

- [設定優先度](#configuration-priority)
- [API キー](#api-keys)
- [モデル設定](#model-settings)
- [システム設定](#system-settings)
- [音声設定](#voice-settings)
- [ヘルプシステム設定](#help-system-settings)
- [開発設定](#development-settings)
- [コンテナ設定](#container-settings)
- [インストールオプション](#install-options)
- [PDF 処理設定](#pdf-processing-settings)

## 設定優先度 :id=configuration-priority

アプリが使うモデルは、次の順（高いものから）で決まります。

1. **アプリの `llm` ブロックに書いた `model`**
   - モデルを書いたアプリは、下の設定にかかわらずそのモデルを使います
2. **環境変数**（`~/monadic/config/env`）。`OPENAI_DEFAULT_MODEL` など
3. **プロバイダーの既定値**（`model_spec.js` の `providerDefaults`）

### 例

OpenAI の既定のモデルの場合：
- `~/monadic/config/env` に `OPENAI_DEFAULT_MODEL=<model-id>` があれば、それを使います
- なければ、`providerDefaults` の OpenAI のチャットのモデルの最初のものを使います

アプリは起動するときに、まだ設定されていない `*_DEFAULT_MODEL`（Ollama を除く）に、プロバイダーの既定値を `~/monadic/config/env` へ書き込みます。それ以降は、ファイルの値が使われます。新しい既定値に合わせるときは、その行を消すか、値を変えてください。

> **注意**：既定のモデルは、`docker/services/ruby/public/js/monadic/model_spec.js` の `providerDefaults` にあります。

## APIキー :id=api-keys

| 変数 | 説明 | 必須 | 例 |
|------|------|------|-----|
| `OPENAI_API_KEY` | GPT のモデル用の OpenAI の API キー | はい（OpenAI のアプリ） | `sk-...` |
| `ANTHROPIC_API_KEY` | Claude のモデル用の Anthropic の API キー | はい（Claude のアプリ） | `sk-ant-...` |
| `GEMINI_API_KEY` | Gemini のモデル用の Google の API キー | はい（Gemini のアプリ） | `AIza...` |
| `MISTRAL_API_KEY` | Mistral AI の API キー | はい（Mistral のアプリ） | `...` |
| `COHERE_API_KEY` | Cohere の API キー | はい（Cohere のアプリ） | `...` |
| `DEEPSEEK_API_KEY` | DeepSeek の API キー | はい（DeepSeek のアプリ） | `...` |
| `XAI_API_KEY` | Grok のモデル用の xAI の API キー | はい（Grok のアプリ） | `xai-...` |
| `ELEVENLABS_API_KEY` | TTS、Scribe の音声認識、Music Generator の ElevenLabs Music 用の ElevenLabs の API キー | はい（ElevenLabs の声） | `...` |
| `TAVILY_API_KEY` | Web 検索用の Tavily の API キー。[プロバイダー機能の概要](../basic-usage/basic-apps.md#provider-capabilities)を参照 | Tavily で Web を検索するとき | `tvly-...` |

### APIキーを 1Password から読み込む :id=onepassword-references

`~/monadic/config/env` の値には、キーそのものの代わりに 1Password のシークレット参照を書けます。

```
OPENAI_API_KEY=op://Dev/OpenAI/credential
```

`op://` で始まらない値は、書かれた値をそのまま使います。

- **必要なもの**: アプリを動かすコンピュータの 1Password のデスクトップアプリと [1Password CLI](https://developer.1password.com/docs/cli/)（`op`）。デスクトップアプリで **Settings → Developer → Integrate with 1Password CLI** をオンにしておく必要があります。この設定は macOS・Windows・Linux で共通です。Windows では、先に 1Password で Windows Hello をオンにします。Linux では、先に **Settings → Security → Unlock using system authentication** をオンにします。これには PolKit と、PolKit の認証エージェントが動いていることが必要です。Snap と Flathub で配布されている 1Password は、この連携に対応していません。詳しくは [1Password の手順](https://developer.1password.com/docs/cli/app-integration/)を参照してください。ターミナルで手動でサインインしたときに設定されるセッションの環境変数は、デスクトップから起動したアプリには渡りません。アプリは `PATH` と、一般的なインストール先から `op` を探します。
- **読み込むとき**: Start を押したときに、すべての参照を 1 回の `op` の呼び出しで読み込みます。1Password の確認は通常 1 回です。この呼び出しが失敗した場合は、どの参照が失敗したかを調べるために 1 つずつ読み直すので、1Password が再び確認を求めることがあります。すべての参照を読み込めたら、値はアプリを終了するまで保持し、Restart やコンテナの再起動では読み直しません。読み込めなかった参照がある場合は、次の Start か Restart で読み直します。設定で参照を変えた場合は、次の Start で読み直します。
- **値の置き場所**: `~/monadic/config/env` には参照のまま残ります。値はアプリのメモリに置き、メモリ上のマウント（tmpfs）を通して Ruby のコンテナに渡します。ファイル、コンテナの設定、コンテナの環境変数には書かず、ログにも出しません。メモリ上のマウントは Docker の仮想マシンのメモリにあり、そのメモリがディスクにスワップされるかどうかは Docker Desktop の動作によります。
- **読み込めなかったとき**: コンソールに、キーの名前と理由（`op` が見つからない、1Password がロックされているか CLI がサインインしていない、確認が取り消されたか 2 分以内に応答がなかった、項目またはフィールドが見つからない）を表示します。そのキーは次の Start まで未設定として扱い、ほかのキーと機能はそのまま使えます。参照の文字列をキーとしてプロバイダに送ることはありません。
- **アプリより古い Ruby のコンテナ**: 値を使えないため、アプリは値を渡さず、作り直しを促します（**Actions → Build Ruby Container**）。
- **開発モード**（`rake server:debug`）: サーバがホストで動くため、サーバ自身がすべての参照を 1 回の `op` の呼び出しで読み込みます。`op` は `PATH` から、または `MONADIC_OP_CLI` に書いたパスから探します。この呼び出しが失敗すると、参照のあるキーはすべて未設定になり、コンソールにはキーの名前だけを表示します（理由は表示しません）。

## モデル設定 :id=model-settings

> **注意**：既定値は、`docker/services/ruby/public/js/monadic/model_spec.js` の `providerDefaults` を参照してください。下の表は、変数の名前と使い方だけを示します。

| 変数 | 説明 | 例 |
|------|------|-----|
| `OPENAI_DEFAULT_MODEL` | OpenAI のアプリの既定のモデル | `OPENAI_DEFAULT_MODEL=<model-id>` |
| `ANTHROPIC_DEFAULT_MODEL` | Claude のアプリの既定のモデル | `ANTHROPIC_DEFAULT_MODEL=<model-id>` |
| `GEMINI_DEFAULT_MODEL` | Gemini のアプリの既定のモデル | `GEMINI_DEFAULT_MODEL=<model-id>` |
| `MISTRAL_DEFAULT_MODEL` | Mistral のアプリの既定のモデル | `MISTRAL_DEFAULT_MODEL=<model-id>` |
| `COHERE_DEFAULT_MODEL` | Cohere のアプリの既定のモデル | `COHERE_DEFAULT_MODEL=<model-id>` |
| `DEEPSEEK_DEFAULT_MODEL` | DeepSeek のアプリの既定のモデル | `DEEPSEEK_DEFAULT_MODEL=<model-id>` |
| `GROK_DEFAULT_MODEL` | Grok のアプリの既定のモデル | `GROK_DEFAULT_MODEL=<model-id>` |
| `OLLAMA_DEFAULT_MODEL` | Ollama のアプリの既定のモデル | `OLLAMA_DEFAULT_MODEL=<model-id>` |
| `TOKEN_COUNT_SOURCE` | 使用量の表示での出力トークンの数え方。未設定：手元のトークナイザーで数える。`provider_only` か `hybrid`：プロバイダーが返す数を使う | `TOKEN_COUNT_SOURCE=provider_only` |

### UIでのモデル選択 :id=model-selection-in-the-ui

**Model** のメニューには、選んだアプリに勧めるモデルの一覧が表示されます。一覧は、アプリの MDSL の定義か、プロバイダーの既定のモデルの組から来ます。

プロバイダーのすべてのモデルを見るには、Model のラベルの横の **All** のスイッチを切り替えます。「All」では、今のアプリと合わないモデル（たとえば、ツールが要るアプリでのツールを使えないモデル）は除かれます。スイッチの状態はブラウザーの Cookie に保存され、セッションをまたいで保たれます。

## システム設定 :id=system-settings

| 変数 | 説明 | 既定 | 選択肢 |
|------|------|------|--------|
| `UI_LANGUAGE` | 画面の言語 | `en` | `en`、`ja`、`zh`、`ko`、`es`、`fr`、`de` |
| `BROWSER_MODE` | Web の画面を開く場所 | `internal` | `internal`（アプリのウィンドウ）、`external`（ブラウザー） |
| `OPEN_AT_LOGIN` | ログインしたときに Monadic Chat を起動する | `false` | `true`、`false` |
| `MENU_BAR_MODE` | メニューバーやシステムトレイから使う | `false` | `true`、`false` |
| `MAX_STORED_MESSAGES` | セッションを元に戻すためにブラウザーに保存するメッセージの数 | `1000` | 数 |
| `ROUGE_THEME` | シンタックスハイライトのテーマ | `github:light` | [使えるテーマ](../basic-usage/syntax-highlighting.md)を参照 |
| `PRIVACY_FILTER` | Privacy のコンテナを起動し、Privacy Filter を使えるようにする | `true` | `true`、`false` |
| `PRIVACY_LANGS` | Privacy Filter が英語のほかに読み込む言語 | `en` | カンマ区切りのコード（`en`、`de`、`es`、`fr`、`it`、`ja`、`nl`、`pt`、`zh`） |
| `EXTRACTOR_SERVICE` | Knowledge Base Quality Pack のコンテナを使う | `false` | `true`、`false` |
| `EXTRACTOR_LANGS` | Knowledge Base Quality Pack の OCR の言語 | `en,ja,zh,ko` | カンマ区切りのコード |
| `LIBRARY_IMPORT_MAX_BYTES` | Knowledge Base が取り込むファイルの最大の大きさ（バイト） | `104857600`（100 MiB） | 数 |
| `GEMINI_MAX_INLINE_PDF_MB` | Gemini にそのまま送る PDF の最大の大きさ（MB） | `20` | 数 |

> **注意**：Web の画面でコンテキストサイズの設定がオンのときは、保存するメッセージの数もその値で制限されます。

## 音声設定 :id=voice-settings

| 変数 | 説明 | 既定 | 範囲・選択肢 |
|------|------|------|--------------|
| `TTS_DICT_PATH` | TTS の読みの辞書（CSV）のパス。Settings ウィンドウ（"TTS Dictionary File Path"）で設定します。ファイルは `~/monadic/config/TTS_DICT.csv` に写され、サーバーはそれを読みます | （任意） | ファイルのパス |
| `AUTO_TTS_MAX_BYTES` | 応答の後に Auto Speech が読み上げる最大の量（バイト）。長い文は文の切れ目で切ります | `400` | 数 |

> **注意**：音声認識のモデルは環境変数では設定しません。Web の画面の **Speech** パネルで選び、選んだものはブラウザーの Cookie に保存されます。

## ヘルプシステム設定 :id=help-system-settings

| 変数 | 説明 | 既定 |
|------|------|------|
| `HELP_CHUNKS_PER_RESULT` | 検索の結果で、文書ごとに返す断片の数 | `3` |
| `HELP_CHUNK_SIZE` | ドキュメントの断片 1 つの文字数。ヘルプデータを作るとき（`rake help:build`）だけ使います | `3000` |
| `HELP_OVERLAP_SIZE` | 隣り合う断片が重なる文字数。ヘルプデータを作るときだけ使います | `500` |

## 開発設定 :id=development-settings

| 変数 | 説明 | 既定 | 選択肢 |
|------|------|------|--------|
| `MCP_SERVER_ENABLED` | Model Context Protocol のサーバーを有効にする | `false` | `true`、`false` |
| `MCP_SERVER_PORT` | MCP サーバーのポート。パッケージ版アプリでは公開するポートが 3100 に決まっているので、変えるのは開発モードのときだけです | `3100` | ポートの番号 |
| `CONDUIT_TOKEN_BUDGET` | プロバイダーのトークンを使う MCP のツールのトークンの予算 | `1000000` | 数 |
| `CONDUIT_AGENT_WALL_CLOCK` | MCP の `monadic_agent` ツールの時間の上限（秒） | `300` | 数 |
| `EXTRA_LOGGING` | `~/monadic/log/extra.log` への詳しいログを有効にする | `false` | `true`、`false` |

## コンテナ設定 :id=container-settings

| 変数 | 説明 | 既定 | 補足 |
|------|------|------|------|
| `START_HEALTH_TRIES` | 起動時の確認の試行回数 | `20` | [高度な設定](/ja/advanced-topics/advanced-configuration.md#startup-health-tuning)を参照 |
| `START_HEALTH_INTERVAL` | 起動時の確認の間隔（秒） | `2` | [高度な設定](/ja/advanced-topics/advanced-configuration.md#startup-health-tuning)を参照 |
| `AUTO_REFRESH_RUBY_ON_HEALTH_FAIL` | Start のときに Ruby のコンテナが unhealthy なら 1 回再ビルドする | `true` | [高度な設定](/ja/advanced-topics/advanced-configuration.md#startup-health-tuning)を参照 |
| `FORCE_RUBY_REBUILD_NO_CACHE` | Ruby のコンテナの再ビルドで Docker のキャッシュを使わない | `false` | [高度な設定](/ja/advanced-topics/advanced-configuration.md#ruby-rebuild)を参照 |
| `QDRANT_URL` | Qdrant のサービスの URL | `http://qdrant_service:6333`（コンテナの中）/ `http://localhost:6333`（開発モード） | サービスが別の場所にあるときだけ変えます |
| `EMBEDDINGS_URL` | embeddings のサービスの URL | `http://embeddings_service:8000`（コンテナの中）/ `http://localhost:8002`（開発モード） | サービスが別の場所にあるときだけ変えます |

## インストールオプション :id=install-options

Python のコンテナに入れる追加のパッケージを選びます。変えた後は、**Actions → Build Python Container** で作り直してください。同じ Install Options のパネルにある Privacy Filter の言語と Knowledge Base Quality Pack は、[システム設定](#system-settings)にあります。

| 変数 | 説明 | 必要なアプリ | 既定 |
|------|------|--------------|------|
| `INSTALL_LATEX` | LaTeX（図のための最小の組。CJK 対応と dvisvgm を含む） | Syntax Tree、Concept Visualizer | `false` |
| `PYOPT_NLTK` | Natural Language Toolkit | 自然言語処理 | `false` |
| `PYOPT_SPACY` | spaCy（自然言語処理のライブラリ） | 高度な自然言語処理 | `false` |
| `PYOPT_GENSIM` | トピックモデルのライブラリ | テキストの分析 | `false` |
| `PYOPT_LIBROSA` | Music Analysis：librosa と madmom（soundfile、midiutil、pretty_midi を含む） | Music Lab、Music Analyst | `false` |
| `PYOPT_MEDIAPIPE` | 画像認識のフレームワーク（CPU） | 画像の処理 | `false` |
| `PYOPT_TRANSFORMERS` | Hugging Face Transformers と Accelerate（CPU） | 深層学習の自然言語処理 | `false` |
| `IMGOPT_IMAGEMAGICK` | ImageMagick の画像処理 | 高度な画像の操作 | `false` |

### インストールオプションの設定方法

**Settings ウィンドウで（推奨）：**
1. **Actions → Install Options** を選びます。Settings ウィンドウが Install Options の項目で開きます
2. 使うオプションをオンにします
3. **Save** をクリックします
4. **Actions → Build Python Container** を選びます

**設定ファイルで：**
```bash
# ~/monadic/config/env
INSTALL_LATEX=true
PYOPT_NLTK=true
PYOPT_LIBROSA=true
```

### スマートビルドキャッシング

- **オプションも `pysetup.sh` もないとき**：ビルドせず、配布されている Python のイメージをダウンロードします
- **オプションがあるとき**：配布されているイメージをキャッシュにして、お使いのコンピューターでビルドします。作られるのは、オンにしたオプションの層だけです
- **`~/monadic/config/pysetup.sh` があるとき**：いつもお使いのコンピューターでビルドし、スクリプトはビルドの最後に実行されます
- **ビルドが成功した後**：Python のコンテナが動いていれば、新しいイメージから作り直されます。動いていなければ、次の Start で新しいイメージが使われます

最後のビルドのオプションは `~/monadic/log/python_build_options.txt` に書かれます。

### 重要な注意事項

- NLTK と spaCy のオプションが入れるのはパッケージだけです。データセットとモデルは、Python のイメージのビルドの最後に実行される `~/monadic/config/pysetup.sh` でダウンロードしてください
- ビルドに失敗したときは、今のイメージがそのまま使われます

## PDF処理設定 :id=pdf-processing-settings

この設定は、MCP サーバーが Knowledge Base に取り込む PDF に使われます。Web の画面で取り込む PDF には、決まった断片の大きさが使われます。

| 変数 | 説明 | 既定 |
|------|------|------|
| `PDF_RAG_TOKENS` | PDF の断片 1 つのトークン数 | `4000` |
| `PDF_RAG_OVERLAP_LINES` | PDF の断片が重なる行数 | `4` |

## 設定例

### 基本設定
```bash
# ~/monadic/config/env

# Essential API Keys
OPENAI_API_KEY=sk-...
ANTHROPIC_API_KEY=sk-ant-...

# Model Preferences
OPENAI_DEFAULT_MODEL=<model-id>

# UI Settings
ROUGE_THEME=github:light
```

### 高度な設定
```bash
# Web Search
TAVILY_API_KEY=tvly-...

# Development
MCP_SERVER_ENABLED=true
```

## 注意事項

- オンとオフの設定は `true` か `false` で書いてください。ほかの書き方（`1` や `0` など）は、サーバーでは数として読まれ、オンとオフにはなりません
- ファイルのパスは絶対パスで書いてください
- 設定によっては、反映に Monadic Chat の再起動が要ります
- API キーは GUI に表示されません
