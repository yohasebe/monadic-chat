# ベクトルデータベース

Monadic Chat には、ドキュメントやユーザーのアップロード PDF に対する意味検索を可能にするベクトルデータベースシステムが組み込まれています。本ドキュメントでは、このシステムの動作とアプリケーション内での使われ方を説明します。

## 概要 :id=overview

Monadic Chat のベクトルデータベース機能は次のことを行います：
- テキストを数値ベクトル表現（エンベディング）にローカル変換
- これらのベクトルを Qdrant コンテナに、構造化メタデータと共に格納
- キーワード一致ではなく意味的類似性に基づく検索を実現
- PDF Navigator アプリと Monadic Help アプリで利用

パイプライン全体がローカルで完結するため、テキスト埋め込みやベクトル検索のために外部 API キーは不要です。

## 技術的実装 :id=technical-implementation

### サービスコンテナ

ベクトル格納と埋め込み推論は、協調する 2 つのコンテナによって担当されます：

- **`monadic-chat-qdrant-container`** は [Qdrant](https://qdrant.tech) ベクトルデータベースを実行します。ドキュメント、チャンク、それらの埋め込みに加え、フィルタリング/グルーピングに使う payload メタデータを保持します。
- **`monadic-chat-embeddings-container`** は [`intfloat/multilingual-e5-base`](https://huggingface.co/intfloat/multilingual-e5-base) sentence-transformer モデルをラップする小さな FastAPI サービスを実行します。テキストを 768 次元のベクトルへ、ホスト CPU 上で変換します。

両コンテナは Monadic Chat 起動時に自動で立ち上がり、設定不要です。

### テキスト処理フロー

![ベクトルデータベース利用のフロー](../assets/images/rag.png ':size=700')

PDF Navigator アプリでの処理フローは以下の通りです：

1. **テキスト抽出**：
   - PDF を PyMuPDF で生テキストに抽出
   - 設定可能なトークン数（既定：1 セグメントあたり 4000 トークン）でセグメントに分割
   - 文脈維持のため、連続するセグメント間で設定可能な行数（既定：4 行）のオーバーラップを保持
   - これらの値は `~/monadic/config/env` の `PDF_RAG_TOKENS` と `PDF_RAG_OVERLAP_LINES` で調整可能

2. **エンベディング生成**：
   - 各セグメントを embeddings コンテナに送り、`multilingual-e5-base` で 768 次元のベクトルを生成
   - 英語・日本語をはじめ多くの言語を同等の品質で扱える
   - ベクトルは L2 正規化されているため、コサイン類似度はドット積に簡約される

3. **ベクトル格納**：
   - 各セグメントは Qdrant の `pdf_items` コレクションに 1 ポイントとして登録され、ベクトル本体と `{doc_id, text, position, app_key, metadata}` の payload を持つ
   - 各 PDF ごとに `pdf_docs` コレクションへ「アイテム埋め込みの平均」をベクトルに持つ doc 単位のポイントも作成され、ドキュメント単位の類似検索を可能にする

4. **検索プロセス**：
   - ユーザーが質問を入力すると、同じモデル（`query:` プレフィックス付き）でクエリを埋め込み
   - HNSW インデックス上のコサイン類似度で、最も近いセグメントを Qdrant が返す
   - 該当セグメントがユーザーのクエリとともに LLM に渡される
   - LLM はそのセグメントを根拠に回答を生成

## スキーマ :id=database-schema

Qdrant はデータを名前付きコレクションで管理します。Monadic Chat は 4 つを利用します：

- **`pdf_docs`** — アップロードされた PDF 1 件につき 1 ポイント。ベクトル：アイテム埋め込みの平均。Payload：`{title, items, app_key, metadata, created_at}`。
- **`pdf_items`** — チャンク化された各テキストセグメントに 1 ポイント。ベクトル：チャンク埋め込み。Payload：`{doc_id, text, position, app_key, metadata}`。
- **`help_docs`** — ドキュメントファイル 1 件につき 1 ポイント。ベクトル：アイテム埋め込みの平均。Payload：`{title, file_path, section, language, items, is_internal, metadata}`。
- **`help_items`** — ドキュメントの各チャンクに 1 ポイント。ベクトル：チャンク埋め込み。Payload：`{doc_id, text, position, heading, language, is_internal, metadata}`。

すべてのコレクションは 768 次元、コサイン距離、HNSW インデックス（フィルター付き高速検索対応）を使用します。

## アプリ単位の隔離 :id=app-isolation

異なるアプリ経由でアップロードされた PDF は互いに分離されます。各アップロードは payload に `app_key` タグ（例：`pdfnavigatoropenai`）を含み、検索時には常に `app_key` フィルタが付加されます。これにより、以前のアプリごとに別データベースを持つ設計と同等のプライバシー保証を、複数の物理データベースなしに実現しています。

## PDF Navigator での使用 :id=use-in-pdf-navigator

PDF Navigator アプリはこのシステムを使ってドキュメント Q&A を提供します：

1. ユーザーが UI から PDF をアップロード
2. システムが抽出・チャンク化・埋め込み・格納を実行
3. ユーザーが内容について質問
4. ベクトル類似度検索で最も関連するセグメントを取得
5. それらのセグメントが LLM に渡され、回答が生成される

各回答にはどのドキュメントのどのセグメントを情報源としたかが表示されます。

?> PDF ストレージモード（ローカル vs クラウド）については [PDF ストレージ](../basic-usage/pdf_storage.md) を参照してください。

## Monadic Help での使用 :id=use-in-monadic-help

Monadic Help アプリは同じ Qdrant + embeddings スタックを利用しますが、`help_docs` / `help_items` コレクションを参照します。これらはパッケージビルド時に事前構築されます：

1. Monadic Chat のビルド時に、ドキュメントファイルをすべて処理して埋め込みを計算
2. 結果は JSON ダンプ（`help_data/help_db.json`）として Ruby イメージに同梱される
3. 初回起動時、Monadic Chat はそのダンプを Qdrant に 1 度だけロードする
4. ユーザー質問時には、同じ query/passage 埋め込みフローで関連ドキュメントを検索
5. ヒットした内容を LLM に渡して回答を生成

埋め込み推論もストレージもローカルで完結するため、ヘルプシステムは外部プロバイダの API キーがなくても動作します。
