# Ollamaの利用

## セットアップ

OllamaはMonadic Chatのオプション機能として組み込まれています。Ollamaを使用するには：

1. Monadic Chatが停止していることを確認（Actions → Stop）
2. Actions → Build Ollama Containerを選択（これは「Build All」とは別です）
3. ビルドが完了するまで待ちます（初回ビルド時は数分かかる場合があります）
4. Monadic Chatを起動（Actions → Start）
5. OllamaグループにOllamaアプリが表示されます

!> Ollamaコンテナはリソース節約のため「Build All」では自動的にビルドされません。この機能を使用するには明示的に「Build Ollama Container」を選択する必要があります。

## 言語モデルの追加

### olsetup.shを使う方法（推奨）

configディレクトリに`olsetup.sh`ファイルを作成することで、モデルのインストールを自動化できます：

1. `~/monadic/config/olsetup.sh`を作成し、必要なモデルを記述します：

```bash
#!/bin/bash
# olsetup.shの例 - モデルのインストール
# 利用可能なモデルは https://ollama.com/library を参照

echo "Ollamaモデルをインストール中..."

# 必要なモデルをインストール（お好みのモデルに置き換えてください）
ollama pull qwen3:4b
ollama pull gemma3:4b

# 必要に応じてモデルを追加
# ollama pull <model-name>:<tag>

echo "モデルのインストールが完了しました！"
```

2. 実行権限を付与します：
```bash
chmod +x ~/monadic/config/olsetup.sh
```

3. Ollamaコンテナをビルドします（Actions → Build Ollama Container）

モデルはコンテナビルドプロセス中に自動的にインストールされ、`~/monadic/ollama/`に永続的に保存されます。

!> **重要**: `olsetup.sh`を使用する場合、スクリプトで指定したモデルのみがインストールされます。デフォルトモデル（`OLLAMA_DEFAULT_MODEL`環境変数で定義）は、スクリプトに明示的に含めない限り自動的にはインストールされません。

### 手動インストール

`olsetup.sh`が見つからない場合、システムは自動的にデフォルトモデル（`OLLAMA_DEFAULT_MODEL`環境変数で設定可能）をプルします。利用可能なモデルは [Ollama Library](https://ollama.com/library) で確認できます。

さらにモデルを手動で追加するには、ターミナルからOllamaコンテナーに接続します：

```shell
$ docker exec -it monadic-chat-ollama-container bash
$ ollama run <model-name>
```

`ollama`のインタラクティブシェルが起動して、モデルのダウンロードが完了すると、`>>>`プロンプトが表示されます。`/bye`と入力してシェルを終了します。

ターミナルからダウンロードしたモデルは、Ollamaアプリを選択するとモデルのセレクターに選択肢として表示されます。

!> ローカルでダウンロードしたモデルは、ロードに時間がかかる場合があります。コンテナを再構築した後や、Monadic Chatを再起動した後、webインターフェイスにモデルが表示されるまでに時間がかかることがあります。そのような時は少し時間を空けてからwebインターフェイスをリロードしてください。

## 利用可能なアプリ

Ollamaグループでは以下のアプリが利用できます：

| アプリ | 説明 |
|--------|------|
| **Chat** | 汎用会話AIアシスタント。テキストと画像をサポート。 |
| **Chat Plus** | コンテキスト追跡機能付き会話AI。トピック、人物、メモをサイドバーパネルで管理。共有フォルダへのファイル操作もサポート。 |
| **Second Opinion** | 同じプロンプトに対して複数のOllamaモデルのレスポンスを比較。 |

Chat Plusはセッションコンテキスト管理やファイル操作にツール呼び出しを使用します。ツール呼び出しには、関数呼び出しをサポートするOllamaモデルが必要です。

## 技術詳細

- **モデル保存場所**: すべてのモデルはホストマシンの`~/monadic/ollama/`に永続的に保存されます
- **デフォルトモデル**: `OLLAMA_DEFAULT_MODEL`環境変数は`olsetup.sh`が存在しない場合のビルド時ダウンロードモデルを指定
- **モデル選択**: Web UIはOllamaサービスから利用可能な最初のモデルを自動選択します
- **モデルリスト**: アプリはOllamaサービス実行時に利用可能なモデルを動的にチェックします
- **コンテナ管理**: 条件付きビルドのためにDockerプロファイル（profile: `ollama`）を使用します

