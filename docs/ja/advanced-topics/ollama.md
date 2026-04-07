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
ollama pull qwen3:4b
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
| **tools** | ツール利用アプリ (Chat Plus、Coding Assistant) 向け関数呼び出し | `qwen3-vl:*`、`qwen3:*`、`llama3.1`、`mistral` |
| **thinking** | Ollama の `think` パラメータによる推論過程のストリーミング出力 | `qwen3-vl:*-thinking`、`qwen3:*-thinking`、`deepseek-r1:*` |
| **structured output** | JSON Schema による構造化出力（全モデル対応） | 全モデル |

任意のモデルの capability は直接以下のコマンドで確認できます:

```bash
ollama show <model-name>
```

Monadic Chat 起動時に Ollama が一時的に到達不能であった場合は、モデル名ベースのヒューリスティック（例: 名前に `-thinking` を含むモデルは thinking 対応とみなす）にフォールバックします。

## 利用可能なアプリ

Ollamaグループでは以下のアプリが利用できます：

| アプリ | 説明 |
|--------|------|
| **Chat** | 汎用会話AIアシスタント。テキストと画像をサポート。 |
| **Coding Assistant** | コードの提案と説明によるプログラミング支援。共有フォルダへのファイル操作もサポート。 |
| **Language Practice** | 文法訂正付き言語会話練習。 |
| **Mail Composer** | トーン調整可能なメール作成支援。共有フォルダへのファイル操作もサポート。 |
| **Voice Chat** | 音声入出力対応の会話AI。 |

Coding Assistant と Mail Composer はファイル操作にツール呼び出しを使用します。これらのアプリには `tools` capability を持つモデルが必要です（[モデルの機能（Capabilities）](#モデルの機能capabilities)を参照）。Chat は vision 対応モデルを選択した場合、追加で画像入力にも対応します。

## 技術詳細

- **GPUアクセラレーション**: ネイティブOllamaはMetal（macOS）またはCUDA（Linux）によるハードウェアアクセラレーション推論を使用
- **デフォルトモデル**: `~/monadic/config/env`の`OLLAMA_DEFAULT_MODEL`でデフォルトモデルを設定可能
- **接続方法**: Monadic ChatのRubyバックエンド（Docker内）はホストのOllamaに`host.docker.internal:11434`経由で接続
- **モデルリスト**: Ollamaサービス実行時に利用可能なモデルを動的にチェック
- **フォールバック**: Ollamaが起動していない場合、サイレントに失敗するのではなくエラーメッセージを返す
