# ヘルプシステム

Monadic Chat には、プロジェクトのドキュメントを基にした文脈対応のヘルプを提供する AI 搭載ヘルプシステムが組み込まれています。

## 概要 :id=overview

ヘルプシステムは、ローカルの sentence-transformer モデル（`multilingual-e5-base`）を使って、Monadic Chat ドキュメントから検索可能なナレッジベースを構築します。埋め込みはローカルで計算され、Qdrant に格納されます。テキストの埋め込みにもナレッジベース検索にも、外部 API キーは必要ありません。

## 機能 :id=features

- **完全ローカル検索**：埋め込み推論もベクトル格納もマシン上で完結し、ヘルプ検索のためにプロバイダ API キーは不要
- **多言語対応**：`multilingual-e5-base` は英語・日本語などを同等品質で扱える
- **マルチチャンク取得**：1 件の結果あたり複数の関連セクションを返し、包括的な回答を生成しやすくする
- **ビルド時に事前構築された JSON ダンプ**：ヘルプデータベースはパッケージビルド時に生成され、Ruby イメージに同梱されるため、初回起動から検索可能
- **公開ドキュメントのみ**：出荷されるデータベースは公開ドキュメントから構築される。`docs_dev/` も対象に含めたい開発者は `rake help:build_internal` で手元用のデータベースを構築できる

## 必要条件 :id=requirements

- 動作中の `monadic-chat-qdrant-container`（ベクトル格納）
- 動作中の `monadic-chat-embeddings-container`（multilingual-e5-base 推論）

これらは Monadic Chat 起動時に自動で立ち上がります。回答生成に使う chat モデル（Claude / GPT / Gemini など）は引き続き各 API キーを必要としますが、検索ステップ自体には不要です。

## 使い方 :id=usage

### ヘルプへのアクセス :id=accessing-help

1. Monadic Chat を起動し、すべてのコンテナが動作していることを確認
2. アプリメニューから「Monadic Help」を選択
3. 任意の言語で Monadic Chat について質問

### よくある質問 :id=common-questions

- "How do I generate graphs?" → Math Tutor または Mermaid Grapher アプリを提案
- "How can I work with PDFs?" → Knowledge Base に PDF をインポートする方法を説明
- "What voice features are available?" → Voice Chat と音声合成オプションを説明

## ヘルプデータベースの構築 :id=building-help-database

通常のユーザーが手動で構築する必要はありません — リリースには事前構築済みのものが同梱されています。開発者は以下で再生成できます：

```bash
# docs/* からヘルプデータベースを構築（出荷されるのはこちら）
rake help:build

# ゼロから再構築（既存ダンプを削除してから再生成）
rake help:rebuild

# 現在のダンプの統計を表示
rake help:stats

# データベースダンプのパスを表示
rake help:export

# 開発者向け：docs_dev/* も索引化する。生成されたダンプは梱包時に
# 拒否されるため、出荷してはいけない。
rake help:build_internal
```

ビルドパイプラインは、必要に応じて embeddings コンテナを起動し、ドキュメントファイルを処理して `docker/services/ruby/help_data/help_db.json` に JSON ダンプを書き出します。このダンプは Ruby Docker イメージのビルド時に組み込まれます。

## アーキテクチャ :id=architecture

### 格納 :id=storage

ヘルプシステムは共有の `monadic-chat-qdrant-container` 内に 2 つの Qdrant コレクションを使います：

- **`help_docs`** — ドキュメントファイル 1 件につき 1 ポイント。ベクトルは各アイテム埋め込みの平均で、ドキュメント単位の関連度ランキングが可能。
  - Payload：`title`、`file_path`、`section`、`language`、`items`（数）、`is_internal`、`metadata`

- **`help_items`** — チャンク化された各テキスト片につき 1 ポイント。
  - Payload：`doc_id`、`text`、`position`、`heading`、`language`、`is_internal`、`metadata`

両コレクションとも、768 次元・コサイン距離・HNSW インデックスを使用します。

### ビルド時パイプライン :id=build-time-pipeline

1. **ドキュメント処理**：
   - `rake help:build` が `scripts/utilities/process_documentation.rb` を実行
   - Markdown を既定でチャンクサイズ 3000 文字、オーバーラップ 500 文字で分割
   - 階層的な見出しパスを payload メタデータに保存

2. **埋め込み生成**：
   - 各チャンクは「passage」として embeddings コンテナへ送信
   - サービス側で e5 の `passage:` プレフィックスを付与し、L2 正規化済みの 768 次元ベクトルを返す
   - ドキュメントごとに、その項目の埋め込み平均をベクトルとして持つ doc 単位のポイントも作成

3. **JSON ダンプの書き出し**：
   - 処理結果を `docker/services/ruby/help_data/help_db.json` に書き出し
   - 短いフィンガープリント（`help_data/export_id.txt`）でビルドキャッシュを失効判定
   - Ruby Docker イメージのビルド時にダンプを焼き込み

### 実行時パイプライン :id=runtime-pipeline

1. **ブートストラップ**：
   - 初回起動時、Monadic Chat は `help_docs` と `help_items` コレクションが存在することを確認
   - 空の場合、`Monadic::Help::DumpLoader` が同梱 JSON ダンプを読み込み、一括インポート
   - コレクションが既に投入済みであれば、以降の起動ではインポートをスキップ

2. **検索**：
   - ユーザーの質問は同じモデルで `query:` プレフィックス付きに埋め込み
   - Qdrant が HNSW 検索で最も類似するアイテムを返す
   - Help アプリはドキュメント単位で結果をグループ化し、最も関連するチャンクを提示

## 設定変数 :id=configuration-variables

ヘルプシステムは `~/monadic/config/env` の環境変数で設定できます：

- `HELP_CHUNK_SIZE`：チャンクあたりの文字数（既定：3000）
  - 大きいほど文脈は豊富だが検索精度が下がる場合がある

- `HELP_OVERLAP_SIZE`：チャンク間でのオーバーラップ文字数（既定：500）
  - 隣接チャンク間の連続性を提供

- `HELP_CHUNKS_PER_RESULT`：検索結果に含めるチャンク数（既定：3）

- `HELP_DATA_DUMP`：JSON ダンプのパスを上書き（既定：Ruby コンテナ内の `/monadic/help_data/help_db.json`）

例：
```
HELP_CHUNK_SIZE=4000
HELP_OVERLAP_SIZE=600
HELP_CHUNKS_PER_RESULT=5
```

## 開発 :id=development

### ドキュメントの追加 :id=adding-documentation

1. `docs/` ディレクトリにマークダウンファイルを追加・編集
2. `rake help:build` を実行して JSON ダンプを再生成
3. 新しいダンプを焼き込むため Ruby コンテナをリビルド

`docs_dev/` 以下の内部ノートは出荷されるデータベースには含まれません。手元で
検索したい場合は代わりに `rake help:build_internal` を使います。なおダンプが
読み込まれるのは Qdrant のコレクションが空のときだけなので、既存の環境では
該当する 2 つのコレクションを削除してから新しいダンプを反映させます。

### 処理の詳細 :id=processing-details

- **セクション解析**：4 段までのマークダウン見出しを追跡し、各チャンクは階層見出しパスを保持
- **言語フィルタリング**：英語ドキュメント処理時、`/ja/`、`/zh/`、`/ko/` 以下のファイルは除外（言語別に個別構築する前提）
- **内部ドキュメント**：`docs_dev/*.md` を含めるのは `rake help:build_internal` だけ。`rake help:build` は `--public-only` を渡し、これが `DEBUG_MODE` に優先するため、開発環境から走らせても内部ドキュメントが出荷用ダンプに混入しない

## パフォーマンスメモ :id=performance-notes

### チャンクサイズの目安 :id=chunk-size-guidelines

- **技術文書**：コード例を保持するため大きめ（4000-5000）
- **FAQ・短文**：精緻なマッチには小さめ（2000-3000）
- **一般文書**：既定（3000）が広く適合

### 検索品質 :id=search-quality

- 回答が不十分に見える場合は `HELP_CHUNKS_PER_RESULT` を増やす
- 検索呼び出しの `top_n` を調整して結果数を増やす
- 具体的な検索語句を使うとマッチが改善

## 制限事項 :id=limitations

- 回答生成に使う chat モデル（Claude、GPT 等）は引き続き各プロバイダの API キーが必要 — 検索ステップのみがローカル
- 言語によりカバレッジ・精度は異なる（spaCy / sentence-transformer は言語ごとに異なるコーパスで学習）

## トラブルシューティング :id=troubleshooting

### よくある問題 :id=common-issues

1. **ヘルプ検索が結果を返さない**
   - JSON ダンプの存在を確認：`ls docker/services/ruby/help_data/help_db.json`
   - 両コンテナの動作を確認：`docker ps | grep -E 'qdrant|embeddings'`
   - `rake help:rebuild` でダンプを再生成

2. **検索結果が貧弱**
   - チャンクサイズを大きくして文脈を増やす
   - `rake help:rebuild` でデータベースを再構築
   - ドキュメント自体に十分な記述があるか確認

3. **ビルドが "embeddings_service did not become ready" で失敗**
   - embeddings イメージが build されているか確認：`docker images | grep monadic-embeddings`
   - コンテナログを確認：`docker logs monadic-chat-embeddings-container`
   - 初回起動時はモデルロードに 30-60 秒かかる場合あり

4. **アップグレード後にヘルプコレクションが空のまま**
   - Ruby アプリはコレクションが空のときのみ JSON ダンプをロードする
   - Qdrant API でコレクションを手動削除して Ruby コンテナを再起動するか、Ruby コンテナを再ビルドして同梱ダンプを再ロード
