# Ollamaの利用

## セットアップ

Monadic Chatはホストマシンで動作するOllamaに直接接続します。これにより完全なGPUアクセラレーション（macOSのMetal、LinuxのCUDA）が利用でき、専用のDockerコンテナが不要になります。

### 1. Ollamaのインストール

お使いのOSに合わせてOllamaをダウンロード・インストールしてください：

- **macOS**: [ollama.comからダウンロード](https://ollama.com/download/mac)
- **Windows**: [ollama.comからダウンロード](https://ollama.com/download/windows)
- **Linux**: `curl -fsSL https://ollama.com/install.sh | sh`

### 2. モデルの取得

インストール後、少なくとも1つのモデルを取得してください。軽量なテキスト専用スターター：

```bash
ollama pull gemma4:e4b
```

Vision・ツール呼び出し・Thinking を 1 つのモデルで扱いたい場合：

```bash
ollama pull qwen3-vl:8b-thinking
```

利用可能なモデルは [Ollama Library](https://ollama.com/library) で確認できます。Monadic Chat が各モデルの機能にどう適応するかは下記の[モデルの機能（Capabilities）](#モデルの機能capabilities)セクションを参照してください。

### 3. Ollamaの起動

Monadic Chatを起動する前に、Ollamaが動作していることを確認してください。macOSとWindowsではOllamaアプリはログイン時に自動起動します。Linuxでは手動で起動が必要な場合があります：

```bash
ollama serve
```

!> **Linuxユーザーへの注意**: デフォルトではOllamaは`127.0.0.1`（localhost）のみでリッスンします。Monadic ChatのバックエンドはDockerコンテナ内で動作し、`host.docker.internal`経由でホストに接続します。Linuxではこのアドレスはlocalhostではなく、Dockerブリッジのゲートウェイ IPに解決されるため、デフォルト設定ではOllamaに接続できません。Dockerコンテナからの接続を許可するには、`OLLAMA_HOST=0.0.0.0 ollama serve`で起動するか、Ollamaアプリの設定で**「Expose Ollama to the network」**を有効にしてください。macOSやWindowsではDocker Desktopが透過的に処理するため、この設定は不要です。

### 4. Monadic Chatの起動

通常通りMonadic Chatを起動してください。OllamaグループにOllamaアプリが表示されます。Ollamaが起動していない場合、使用しようとするとエラーメッセージが表示されます。

## 言語モデルの追加

`ollama`コマンドを使用して、システム上で直接モデルを管理できます：

```bash
# インストール済みモデルの一覧
ollama list

# 新しいモデルの取得
ollama pull gemma3:4b

# モデルの実行（未取得の場合はダウンロード）
ollama run llama3.2

# モデルの削除
ollama rm <model-name>
```

インストールしたモデルは、Ollamaアプリのモデル選択で自動的に利用可能になります。新しく追加したモデルがすぐに表示されない場合は、Webインターフェースをリロードしてください。

## モデルの機能（Capabilities）

Monadic Chat は Ollama の `/api/show` エンドポイントに問い合わせて、各モデルがサポートする機能をランタイムで検出します。UIもこれに応じて自動的に変化します: Vision対応モデルを選択したときだけ画像アップロードボタンが出現し、推論を出力するモデルでのみ Thinking パネルが表示され、ツール利用アプリは関数呼び出し対応モデルに対してのみ tool 定義を送信します。

検出される機能:

| 機能 | 説明 | モデル例 |
|------|------|---------|
| **vision** | 画像入力対応（マルチモーダル） | `qwen3-vl:*`、`llava`、`llama3.2-vision` |
| **tools** | ツール利用アプリ (Coding Assistant、Knowledge Base) 向け関数呼び出し | `qwen3-vl:*`、`qwen3:*`、`llama3.1`、`mistral` |
| **thinking** | Ollama の `think` パラメータによる推論過程のストリーミング出力 | `qwen3-vl:*-thinking`、`qwen3:*-thinking`、`deepseek-r1:*` |
| **structured output** | JSON Schema による構造化出力（全モデル対応） | 全モデル |

任意のモデルの capability は直接以下のコマンドで確認できます:

```bash
ollama show <model-name>
```

Monadic Chat 起動時に Ollama が一時的に到達不能であった場合は、モデル名ベースのヒューリスティック（例: 名前に `-thinking` を含むモデルは thinking 対応とみなす）にフォールバックします。

> **`-thinking` モデルバリアントに関する注意**: 名前に `-thinking` を含むモデル（例: `qwen3-vl:8b-thinking`）は、Show Thinking トグルをオフにしても内部で常に推論トークンを生成します。そのため応答が遅くなることは避けられません。高速な応答が必要な場合は、`gemma4:e4b` のような非 thinking バリアントを使用してください。これらのモデルはトグルオフ時に thinking を完全に無効化できます。

## ツール呼び出しに対応したおすすめモデル

Monadic Chat の主要機能（ウェブ検索、ファイル操作、エージェント機能、構造化されたツール呼び出し）には、`tools` capability を持つモデルが必要です。`/api/show` の capabilities 一覧に `tools` を含まない Ollama モデルを選択すると、サイドバーに黄色の **No tool calling** インジケータが表示され、Coding Assistant / Mail Composer / Knowledge Base のツール機能は動作しません。

以下のファミリーは全てツール呼び出しに対応しており、Q4 量子化で 16 GB のユニファイドメモリに収まります。サイズは量子化後の VRAM フットプリントの目安です。正確な値は `ollama show <model>` で確認してください。

| ファミリー | タグ | サイズ目安 (Q4) | 備考 |
|-----------|------|----------------|------|
| Qwen3-VL | `qwen3-vl:4b` / `qwen3-vl:8b` | 3 GB / 6 GB | Vision + tools + thinking。CJK 対応強い。 |
| Qwen3 | `qwen3:4b` / `qwen3:8b` | 2.5 GB / 5 GB | テキスト専用、tools + thinking。 |
| Llama 3.1 | `llama3.1:8b` | 5 GB | tools、vision なし。 |
| Llama 3.2 | `llama3.2:3b` | 2 GB | tools、vision なし。フットプリント小。 |
| Mistral | `mistral:7b-instruct`（およびツール呼び出しバリアント）| 4 GB | tools、vision なし。タグに `-instruct` または `-tool-use` を含むものを使用。 |
| Phi-3.5 Mini | `phi3.5:3.8b` | 2.5 GB | tools、vision なし。Microsoft 公式。 |

エージェント機能を必要としないテキストのみのチャットには、`gemma3:4b` や `gemma4:e4b` のような非ツール対応モデルでも問題ありません。サイドバーの警告は情報提示のみで、利用を妨げるものではありません。

## 利用可能なアプリ

Ollamaグループでは以下のアプリが利用できます：

| アプリ | 説明 |
|--------|------|
| **Chat** | 汎用会話AIアシスタント。テキストと画像をサポート。 |
| **Coding Assistant** | コードの提案と説明によるプログラミング支援。共有フォルダへのファイル操作もサポート。 |
| **Knowledge Base** | プロジェクト全体の Knowledge Base に保存された会話・文書の管理。検索、アプリ間での共有設定、外部コンテンツの取り込みに対応。 |
| **Language Practice** | 文法訂正付き言語会話練習。 |
| **Mail Composer** | トーン調整可能なメール作成支援。共有フォルダへのファイル操作もサポート。 |
| **Voice Chat** | 音声入出力対応の会話AI。 |

Coding Assistant と Mail Composer はファイル操作に、Knowledge Base は Library 操作にツール呼び出しを使用します。これらのアプリには `tools` capability を持つモデルが必要です（[モデルの機能（Capabilities）](#モデルの機能capabilities)を参照）。Chat は vision 対応モデルを選択した場合、追加で画像入力にも対応します。

## 技術詳細

- **GPUアクセラレーション**: ネイティブOllamaはMetal（macOS）またはCUDA（Linux）によるハードウェアアクセラレーション推論を使用
- **デフォルトモデル**: `~/monadic/config/env`の`OLLAMA_DEFAULT_MODEL`でデフォルトモデルを設定可能
- **接続方法**: Monadic ChatのRubyバックエンド（Docker内）はホストのOllamaに`host.docker.internal:11434`経由で接続
- **モデルリスト**: Ollamaサービス実行時に利用可能なモデルを動的にチェック
- **フォールバック**: Ollamaが起動していない場合、サイレントに失敗するのではなくエラーメッセージを返す
