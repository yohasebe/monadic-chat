# ヘルプシステム

Monadic Chat Help アプリは、Monadic Chat のドキュメントにもとづいて、Monadic Chat についての質問に答えます。

## 概要 :id=overview

ドキュメントは、お使いのコンピューターの上で動く多言語の埋め込みモデルでベクトルに変換され、Qdrant に保存されます。ヘルプデータのインストールにも検索にも、API キーは要りません。

## 機能 :id=features

- **ローカルだけでの検索**：埋め込みの計算もベクトルの保存も、お使いのコンピューターの上で行われます。ヘルプの検索にプロバイダーの API キーは要りません
- **多言語**：英語、日本語など、多くの言語で質問できます
- **複数の断片の取得**：1 件の結果ごとに、関連する節をいくつも返します
- **同梱のデータ**：ヘルプデータは Monadic Chat のパッケージを作るときにドキュメントから作られ、Ruby のイメージに含まれています。インストールするかどうかは利用者が選びます
- **公開ドキュメントだけ**：同梱のデータとインストールの機能が扱うのは、公開ドキュメントだけです

## 必要条件 :id=requirements

- `monadic-chat-qdrant-container` が動いていること（ベクトルの保存）
- `monadic-chat-embeddings-container` が動いていること（埋め込みモデル）

どちらも Monadic Chat とともに自動で起動します。回答を作るチャットのモデルには、そのプロバイダーの API キーが必要です。ヘルプデータのインストールと検索には、API キーは要りません。

## 使い方 :id=usage

### ヘルプへのアクセス :id=accessing-help

1. Monadic Chat を起動し、すべてのコンテナが動いていることを確かめます
2. アプリのメニューから「Monadic Chat Help」を選びます
3. サイドバーの **Help Data** パネルから、同梱のデータをインストールします。同じパネルは **Monadic Chat Info → Help Data** からも開け、こちらは API キーがなくても使えます
4. インストールが終わったら、どの言語でも Monadic Chat について質問できます

ヘルプの検索は、利用者が自分でインストールして使う機能です。Monadic Chat の起動や再ビルドでは、ヘルプデータはインストールも置き換えもされません。パネルに、インストールの状態と進み具合が表示されます。

同梱のデータがインストール済みのデータより新しいと、パネルに更新が表示されます。更新のボタンで、インストール済みのヘルプデータを入れ替えてください。入れ替えが始まるまでは、インストール済みのヘルプを検索できます。インストール済みのデータの版を確かめられないときは、パネルが再インストールを求めます。

インストール・更新・再インストール・再試行のボタンは、確認のダイアログなしで処理を始めます。入れ替えの間は、ヘルプの検索は使えません。**Knowledge Base と会話のライブラリのデータはそのまま残ります。** 失敗したときは、表示された理由を確かめ、パネルからやり直してください。

### よくある質問 :id=common-questions

- "How do I generate graphs?" → Math Tutor か Mermaid Grapher のアプリを勧めます
- "How can I work with PDFs?" → Knowledge Base に PDF を取り込む方法を説明します
- "What voice features are available?" → Voice Chat と音声合成のオプションを説明します

## ヘルプデータベースの構築 :id=building-help-database

ヘルプデータはリリースに含まれているので、利用者が作る必要はありません。開発者は次のコマンドで作り直せます。

```bash
# Build the help database from docs/* (this is what ships)
rake help:build

# Rebuild from scratch (deletes existing dump first)
rake help:rebuild

# Show statistics for the current dump
rake help:stats

# Print the path of the database dump
rake help:export

# Developers only: also index docs_dev/*. The resulting dump is rejected
# by packaging and the help data installer.
rake help:build_internal
```

ビルドの処理は、embeddings コンテナが動いていなければ起動し、ドキュメントのファイルを処理して、`docker/services/ruby/help_data/help_db.json` に JSON のダンプを書き出します。このダンプは、Ruby の Docker イメージのビルドのときにイメージに組み込まれます。

## アーキテクチャ :id=architecture

### 格納 :id=storage

ヘルプデータは、Knowledge Base や会話のライブラリのデータとは分けて、ローカルの Qdrant に保存されます。文書全体とその断片の両方を索引にするので、検索では関連する節を返せます。ヘルプデータを更新しても、入れ替わるのはヘルプの索引だけです。

### ビルド時パイプライン :id=build-time-pipeline

1. **ドキュメントの処理**：
   - `rake help:build` が `scripts/utilities/process_documentation.rb` を実行します
   - Markdown のファイルを、既定で 1 つ 3000 文字、重なり 500 文字の断片に分けます
   - 断片ごとに、見出しの階層の道筋を保存します

2. **埋め込みの生成**：
   - 断片は「passage」として embeddings コンテナに送られます
   - サービスはモデルが求める `passage:` の前置きを付け、L2 正規化された 768 次元のベクトルを返します
   - 文書ごとに、その断片のベクトルの平均もベクトルとして作ります

3. **JSON のダンプの書き出し**：
   - 処理の結果を `docker/services/ruby/help_data/help_db.json` に書き出します
   - Ruby の Docker イメージのビルドのときに、ダンプがイメージに組み込まれます

### 実行時パイプライン :id=runtime-pipeline

1. **インストール**：
   - 利用者が **Help Data** パネルからインストールを始めます
   - Monadic Chat が同梱のデータを確かめ、前のヘルプの索引を置き換えて、結果を確かめます
   - インストールが終わると検索が使えるようになり、次の起動からはインストール済みのデータを使います
   - より新しい同梱のデータは更新として表示され、利用者が選んだときだけインストールされます

2. **検索**：
   - 利用者の質問は、同じモデルで `query:` の前置きを付けて埋め込まれます
   - Qdrant が HNSW の検索で、最も似ている項目を返します
   - Help アプリは結果を文書ごとにまとめ、関連の強い断片を示します

## 設定変数 :id=configuration-variables

次の変数は `~/monadic/config/env` から読み込まれます。

Help アプリが使うもの：

- `HELP_CHUNKS_PER_RESULT`：検索の結果 1 件ごとに返す断片の数（既定：3）
- `HELP_DATA_DUMP`：インストールで使う JSON のダンプ（既定：Ruby コンテナの中の `/monadic/help_data/help_db.json`）。パスを変えても、データはインストールされません

`rake help:build` でヘルプデータを作るときだけ使うもの：

- `HELP_CHUNK_SIZE`：断片 1 つの文字数（既定：3000）。大きいほど 1 件の結果の文脈は増え、一致の精度は下がります
- `HELP_OVERLAP_SIZE`：隣り合う断片が重なる文字数（既定：500）

例：
```
HELP_CHUNKS_PER_RESULT=5
```

## 開発 :id=development

### ドキュメントの追加 :id=adding-documentation

1. `docs/` のディレクトリで Markdown のファイルを追加・編集します
2. `rake help:build` を実行して、JSON のダンプを作り直します
3. 新しいダンプを使うように、Ruby コンテナを再ビルドして作り直します
4. **Help Data** パネルを開き、ヘルプデータをインストールまたは更新します

再ビルドしただけでは、動いているヘルプのデータベースは変わりません。`docs_dev/` の内部のメモは、同梱のデータベースには入りません。`rake help:build_internal` は開発用のダンプを作りますが、内部の内容は、パッケージを作るときにもヘルプデータのインストールのときにも拒否されます。`DEBUG_MODE=true` でも同じです。

### 処理の詳細 :id=processing-details

- **節の解析**：4 段までの Markdown の見出しをたどり、断片ごとに見出しの階層の道筋を持たせます
- **言語の絞り込み**：英語のドキュメントを処理するときは、`/ja/`、`/zh/`、`/ko/` の下のファイルを除きます。言語ごとに別に作るためです
- **内部のドキュメント**：`docs_dev/*.md` を含めるのは `rake help:build_internal` だけです。`rake help:build` は `--public-only` を渡し、これが `DEBUG_MODE` より優先されるので、開発の環境で実行しても内部のドキュメントは出荷用のダンプに入りません

## パフォーマンスメモ :id=performance-notes

### チャンクサイズの目安 :id=chunk-size-guidelines

`HELP_CHUNK_SIZE` でヘルプデータを作るときの目安です。

- **技術文書**：コードの例を切らないように大きめ（4000〜5000）
- **FAQ・短い内容**：一致を細かくするために小さめ（2000〜3000）
- **一般の内容**：既定（3000）でたいていうまくいきます

### 検索品質 :id=search-quality

- 回答が足りないように見えるときは、`HELP_CHUNKS_PER_RESULT` を増やします
- 具体的な言葉で質問すると、よく一致します

## 制限事項 :id=limitations

- 質問に答えるチャットのモデルには、そのプロバイダーの API キーが必要です。インストールと検索には API キーは要りません
- 検索の質は言語によって違います

## トラブルシューティング :id=troubleshooting

### よくある問題 :id=common-issues

1. **ヘルプの検索が使えない、または結果が返らない**
   - **Help Data** パネルで状態を確かめ、求められたらインストールまたは再インストールします
   - インストール中なら終わるのを待ちます。失敗したら、表示された理由を確かめてやり直します
   - 両方のコンテナが動いているか確かめます：`docker ps | grep -E 'qdrant|embeddings'`

2. **検索の結果がよくない**
   - ヘルプデータの更新があればインストールします
   - 質問に答えられるだけの記述がドキュメントにあるか確かめます
   - ドキュメントを書く開発者は、断片の大きさを調整し、`rake help:rebuild` でダンプを作り直して、[ドキュメントの追加](#adding-documentation)の手順でインストールします

3. **ビルドが "embeddings_service did not become ready" で失敗する**
   - embeddings のイメージがビルドされているか確かめます：`docker images | grep monadic-embeddings`
   - コンテナのログを確かめます：`docker logs monadic-chat-embeddings-container`
   - モデルの読み込みが終わるのを待ってから、ビルドをやり直します

4. **Help Data パネルが操作を求める**
   - **Help Data** パネルを開きます
   - インストールされていなければインストール、更新があれば更新、前の版を確かめられなければ再インストールします
   - コンテナの再起動や再ビルドでは、ヘルプデータは入れ替わりません。パネルから操作してください
