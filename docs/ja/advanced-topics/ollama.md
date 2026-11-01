# Ollama の利用

## セットアップ

Monadic Chat は、Docker の外、お使いのコンピューターの上で動く Ollama に接続します。Ollama はコンピューターの GPU（macOS では Metal、Linux では CUDA）を使います。

### 1. Ollama のインストール

お使いの OS 用の Ollama をダウンロードしてインストールします。

- **macOS**：[ollama.com からダウンロード](https://ollama.com/download/mac)
- **Windows**：[ollama.com からダウンロード](https://ollama.com/download/windows)
- **Linux**：`curl -fsSL https://ollama.com/install.sh | sh`

### 2. モデルの取得

インストールしたら、モデルを 1 つ以上取得します。

```bash
ollama pull <model-name>
```

使えるモデルは [Ollama Library](https://ollama.com/library) にあります。Monadic Chat のツールの機能を使うには、`tools` の能力を持つモデルを選んでください。[モデルの能力](#model-capabilities)を参照してください。

### 3. Ollama の起動

Ollama のアプリを使うときは、Ollama が動いている必要があります。macOS と Windows では、Ollama のアプリはログイン時に起動します。Linux では、動いていなければ自分で起動します。

```bash
ollama serve
```

!> **Linux の場合**：Ollama は既定で `127.0.0.1` だけで待ち受けます。Monadic Chat のバックエンドは Docker コンテナの中で動き、`host.docker.internal` を通してホストに接続しますが、Linux ではこれは `127.0.0.1` ではありません。`OLLAMA_HOST=0.0.0.0 ollama serve` で Ollama を起動するか、Ollama のアプリの設定で **"Expose Ollama to the network"** をオンにしてください。macOS と Windows では必要ありません。

### 4. Monadic Chat の起動

いつもどおり Monadic Chat を起動します。Ollama のアプリは Ollama のグループにあります。Ollama が動いていないと、アプリを使ったときにエラーのメッセージが表示されます。

## 言語モデルの追加

モデルは `ollama` コマンドで管理します。

```bash
# List installed models
ollama list

# Pull a model
ollama pull <model-name>

# Remove a model
ollama rm <model-name>
```

インストールしたモデルは、Ollama のアプリのモデルのメニューに表示されます。加えたばかりのモデルが表示されないときは、Web の画面を再読み込みしてください。

## モデルの能力 :id=model-capabilities

Monadic Chat は、Ollama の `/api/show` からモデルごとの能力を読み取り、画面をそれに合わせます。

| 能力 | 使えるようになること |
|------|----------------------|
| **vision** | 画像の入力。画像のボタンは、この能力を持つモデルのときだけ表示されます。 |
| **tools** | ツールの呼び出し。Web 検索と、Coding Assistant・Mail Composer・Knowledge Base のツールの機能です。 |
| **thinking** | 推論の出力。思考のパネルに表示されます。Show Thinking で、オンとオフを切り替えます。 |

構造化出力（JSON スキーマに沿った生成）は、どのモデルでも使えます。

モデルの能力を確かめるには：

```bash
ollama show <model-name>
```

`/api/show` からモデルの答えが得られないときは、モデルの名前から推測します（たとえば、名前に `thinking` を含むものは推論のモデル、`vision` や `-vl` を含むものは画像を扱えるモデルとみなします）。また、そのモデルはツールを呼び出せるものとして扱います。

?> モデルによっては、Show Thinking がオフでも、毎回推論を行います。そうしたモデルは、名前に `thinking` を含むことが多く、応答が遅くなります。速さが大事なときは、推論をオフにできるモデルを選んでください。

## ツールを呼び出せないモデル

選んだモデルが `tools` の能力を持たないときは、サイドバーに黄色の **No tool calling** の表示が出ます。そのモデルでは、Web 検索と、Coding Assistant・Mail Composer・Knowledge Base のツールの機能は使えません。ふつうの会話には問題なく使えます。

## 使えるアプリ

Ollama のグループには、次のアプリがあります。

| アプリ | 説明 |
|--------|------|
| **Chat** | 一般的な会話。画像を扱えるモデルを選ぶと、画像も受け付けます。 |
| **Coding Assistant** | プログラミングの手助け。共有フォルダのファイルの操作もできます。 |
| **Knowledge Base** | Knowledge Base の操作。項目の検索・一覧・範囲の変更・取り込み・削除ができます。 |
| **Language Practice** | 外国語での会話の練習と添削。 |
| **Mail Composer** | メールの作成の手助け。共有フォルダのファイルの操作もできます。 |
| **Voice Chat** | 声での会話。 |

Coding Assistant、Mail Composer、Knowledge Base には、`tools` の能力を持つモデルが必要です。

## 技術的な詳細

- **既定のモデル**：`~/monadic/config/env` の `OLLAMA_DEFAULT_MODEL` で設定します。
- **接続**：バックエンドは `host.docker.internal:11434` に接続し、つながらないときは `localhost:11434` に接続します。
- **モデルの一覧**：Ollama が動いている間、モデルの一覧を Ollama から読み取り、30 秒ごとに更新します。
