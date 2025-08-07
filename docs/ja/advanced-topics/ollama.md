# Ollamaの利用

## セットアップ

OllamaはMonadic Chatのオプション機能として組み込まれています。Ollamaを使用するには：

1. Monadic Chatが停止していることを確認（Actions → Stop）
2. Actions → Build Ollama Containerを選択（これは「Build All」とは別です）
3. ビルドが完了するまで待ちます（初回ビルド時は数分かかる場合があります）
4. Monadic Chatを起動（Actions → Start）
5. OllamaグループにChatアプリが表示されます

!> Ollamaコンテナはリソース節約のため「Build All」では自動的にビルドされません。この機能を使用するには明示的に「Build Ollama Container」を選択する必要があります。

## 言語モデルの追加

### olsetup.shを使う方法（推奨）

configディレクトリに`olsetup.sh`ファイルを作成することで、モデルのインストールを自動化できます：

1. `~/monadic/config/olsetup.sh`を作成し、必要なモデルを記述します：

```bash
#!/bin/bash
# olsetup.shの例 - モデルのインストール

echo "Ollamaモデルをインストール中..."

# 必要なモデルをインストール
ollama pull llama3.2:3b
ollama pull gemma2:2b
ollama pull mistral:7b

# 必要に応じてモデルを追加
# ollama pull model-name:size

echo "モデルのインストールが完了しました！"
```

2. 実行権限を付与します：
```bash
chmod +x ~/monadic/config/olsetup.sh
```

3. Ollamaコンテナをビルドします（Actions → Build Ollama Container）

モデルはコンテナビルドプロセス中に自動的にインストールされ、`~/monadic/ollama/`に永続的に保存されます。

!> **重要**: `olsetup.sh`を使用する場合、スクリプトで指定したモデルのみがインストールされます。デフォルトモデル（`OLLAMA_DEFAULT_MODEL`設定変数で定義、未設定の場合は`llama3.2`）は自動的にはインストールされません。デフォルトモデルも必要な場合は、スクリプトに明示的に含める必要があります。

### 手動インストール

`olsetup.sh`が見つからない場合、システムは自動的に`llama3.2`をデフォルトとしてプルします。デフォルトモデルは`~/monadic/config/env`ファイルで`OLLAMA_DEFAULT_MODEL`設定変数を設定することで変更できます。

さらにモデルを手動で追加するには、ターミナルからOllamaコンテナーに接続します：


```shell
$ docker exec -it monadic-chat-ollama-container bash
$ ollama run gemma2:2b
pulling manifest
pulling 7462734796d6... 100% ▕████████████▏ 1.6 GB
pulling e0a42594d802... 100% ▕████████████▏  358 B
pulling 097a36493f71... 100% ▕████████████▏ 8.4 KB
pulling 2490e7468436... 100% ▕████████████▏   65 B
pulling e18ad7af7efb... 100% ▕████████████▏  487 B
verifying sha256 digest
writing manifest
success
>>>
```

`ollama`のインタラクティブシェルが起動して、モデルのダウンロードが完了すると、`>>>`プロンプトが表示されます。`/bye`と入力してシェルを終了します。

ターミナルからダウンロードしたモデルは、Chat（Ollama版）アプリを選択するとモデルのセレクターに選択肢として表示されます。

!> ローカルでダウンロードしたモデルは、ロードに時間がかかる場合があります。Ollamaコンテナのセットアップが完了すると、自動的にOllamaアプリが利用可能になります。

## 技術詳細

- **モデル保存場所**: すべてのモデルはホストマシンの`~/monadic/ollama/`に永続的に保存されます
- **デフォルトモデル**: `OLLAMA_DEFAULT_MODEL`設定変数は`olsetup.sh`が存在しない場合のビルド時ダウンロードモデルを指定（デフォルト: `llama3.2`）
- **モデル選択**: Web UIはOllamaサービスから利用可能な最初のモデルを自動選択します
- **モデルリスト**: アプリはOllamaサービス実行時に利用可能なモデルを動的にチェックします
- **コンテナ管理**: 条件付きビルドのためにDockerプロファイル（profile: `ollama`）を使用します

