# Ollamaの利用

## セットアップ

Monadic Chatはホストマシンで動作するOllamaに直接接続します。これにより完全なGPUアクセラレーション（macOSのMetal、LinuxのCUDA）が利用でき、専用のDockerコンテナが不要になります。

### 1. Ollamaのインストール

お使いのOSに合わせてOllamaをダウンロード・インストールしてください：

- **macOS**: [ollama.comからダウンロード](https://ollama.com/download/mac)
- **Windows**: [ollama.comからダウンロード](https://ollama.com/download/windows)
- **Linux**: `curl -fsSL https://ollama.com/install.sh | sh`

### 2. モデルの取得

インストール後、少なくとも1つのモデルを取得してください：

```bash
ollama pull qwen3:4b
```

利用可能なモデルは [Ollama Library](https://ollama.com/library) で確認できます。

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

## 利用可能なアプリ

Ollamaグループでは以下のアプリが利用できます：

| アプリ | 説明 |
|--------|------|
| **Chat** | 汎用会話AIアシスタント。テキストと画像をサポート。 |
| **Chat Plus** | コンテキスト追跡機能付き会話AI。トピック、人物、メモをサイドバーパネルで管理。共有フォルダへのファイル操作もサポート。 |
| **Coding Assistant** | コードの提案と説明によるプログラミング支援。共有フォルダへのファイル操作もサポート。 |
| **Language Practice** | 文法訂正付き言語会話練習。 |
| **Second Opinion** | 同じプロンプトに対して複数のOllamaモデルのレスポンスを比較。 |

Chat PlusとCoding Assistantはファイル操作などの機能にツール呼び出しを使用します。ツール呼び出しには、関数呼び出しをサポートするOllamaモデルが必要です。

## 技術詳細

- **GPUアクセラレーション**: ネイティブOllamaはMetal（macOS）またはCUDA（Linux）によるハードウェアアクセラレーション推論を使用
- **デフォルトモデル**: `~/monadic/config/env`の`OLLAMA_DEFAULT_MODEL`でデフォルトモデルを設定可能
- **接続方法**: Monadic ChatのRubyバックエンド（Docker内）はホストのOllamaに`host.docker.internal:11434`経由で接続
- **モデルリスト**: Ollamaサービス実行時に利用可能なモデルを動的にチェック
- **フォールバック**: Ollamaが起動していない場合、サイレントに失敗するのではなくエラーメッセージを返す
