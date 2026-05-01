# ベクトルデータベース

Monadic Chat には、ドキュメントやユーザーのアップロード PDF に対する意味検索を可能にするベクトルデータベースシステムが組み込まれています。本ドキュメントでは、このシステムの動作とアプリケーション内での使われ方を説明します。

## 概要 :id=overview

Monadic Chat のベクトルデータベース機能は次のことを行います：
- テキストを数値ベクトル表現（エンベディング）にローカル変換
- これらのベクトルを Qdrant コンテナに、構造化メタデータと共に格納
- キーワード一致ではなく意味的類似性に基づく検索を実現
- Knowledge Base アプリと Monadic Help アプリで利用

パイプライン全体がローカルで完結するため、テキスト埋め込みやベクトル検索のために外部 API キーは不要です。

## 技術的実装 :id=technical-implementation

### サービスコンテナ

ベクトル格納と埋め込み推論は、協調する 2 つのコンテナによって担当されます：

- **`monadic-chat-qdrant-container`** は [Qdrant](https://qdrant.tech) ベクトルデータベースを実行します。ドキュメント、チャンク、それらの埋め込みに加え、フィルタリング/グルーピングに使う payload メタデータを保持します。
- **`monadic-chat-embeddings-container`** は [`intfloat/multilingual-e5-base`](https://huggingface.co/intfloat/multilingual-e5-base) sentence-transformer モデルをラップする小さな FastAPI サービスを実行します。テキストを 768 次元のベクトルへ、ホスト CPU 上で変換します。

両コンテナは Monadic Chat 起動時に自動で立ち上がり、設定不要です。

### テキスト処理フロー

![ベクトルデータベース利用のフロー](../assets/images/rag.png ':size=700')

Knowledge Base のインポートパイプラインの処理フローは以下の通りです：

1. **コンテンツ抽出**：
   - PDF は [PyMuPDF](https://pymupdf.readthedocs.io/en/latest/)（`pymupdf4llm.to_markdown`）で見出し・リスト・表を Markdown として復元
   - Office ファイル（`.docx`/`.xlsx`/`.pptx`）は `python-docx` / `openpyxl` / `python-pptx` で抽出
   - Markdown とソースコードはそのまま読み込み、それぞれ見出し・トップレベル定義をセクション境界とする
   - 抽出後のコンテンツはセクション単位（200〜4000 文字程度）でチャンク化（フォーマットごとの境界ルールあり）

2. **エンベディング生成**：
   - 各セグメントを embeddings コンテナに送り、`multilingual-e5-base` で 768 次元のベクトルを生成
   - 英語・日本語をはじめ多くの言語を同等の品質で扱える
   - ベクトルは L2 正規化されているため、コサイン類似度はドット積に簡約される

3. **ベクトル格納**：
   - 各チャンクは Qdrant の `library_turns` コレクションに 1 ポイントとして登録され、ベクトル本体と `{conversation_id, visibility, turn_idx, text, ...}` の payload を持つ
   - 会話単位のポイントは `library_summaries` コレクションに格納され、title / source / content_type / placeholder summary 埋め込みを保持。ドキュメントレベルのカスケード検索の起点となる
   - `library_trajectory` コレクションは sliding-window の談話状態ベクトルを保持し、軌跡可視化に利用される

4. **検索プロセス**：
   - ユーザーが質問を入力すると、同じモデル（`query:` プレフィックス付き）でクエリを埋め込み
   - HNSW インデックス上のコサイン類似度で、最も近いセグメントを Qdrant が返す
   - 該当セグメントがユーザーのクエリとともに LLM に渡される
   - LLM はそのセグメントを根拠に回答を生成

## スキーマ :id=database-schema

Qdrant はデータを名前付きコレクションで管理します。Monadic Chat は次のコレクションを使用します：

- **`library_summaries`** — 会話/ドキュメント 1 件につき 1 ポイント。Payload：`{conversation_id, visibility, content_type, source, title, language, license, topics, messages, participants, ...}`。検索カスケードの入口、Knowledge Base ブラウズリストの source-of-truth として使用。
- **`library_turns`** — チャンク化された各テキストセグメントに 1 ポイント。ベクトル：チャンク埋め込み。Payload：`{conversation_id, visibility, turn_idx, speaker_id, text, ...}`。`library_search` ツールが利用するメインの RAG 検索単位。
- **`library_trajectory`** — sliding-window の談話状態ごとに 1 ポイント。軌跡可視化に利用。
- **`help_docs` / `help_items`** — Monadic Help のドキュメントインデックス。Ruby イメージにパッケージビルド時に同梱され、初回起動時に Qdrant へロードされる。

すべてのコレクションは 768 次元、コサイン距離、HNSW インデックス（フィルター付き高速検索対応）を使用します。

## 可視性によるフィルタリング :id=visibility

Library エントリは `personal` または `shareable` の `visibility` payload を持ちます。Knowledge Base UI は両方を表示しますが、アプリ横断的に呼ばれる `library_search` ツールは `shareable` のみを返します。これは旧 PDF Navigator 時代の「アプリ単位の物理隔離」モデルを置き換えるもので、プロジェクト全体で 1 つの Library を共有しつつ、外部アクセスを visibility フラグで制御します。

## Knowledge Base での使用 :id=use-in-knowledge-base

Knowledge Base アプリはこのシステムを使って統合的なコンテンツ Q&A を提供します：

1. ユーザーが現在のチャットセッションを保存、または Browse モーダルの **Import file** をクリック
2. システムが抽出・チャンク化・埋め込み・格納を実行（PDF は PyMuPDF、Office は python-docx/openpyxl/python-pptx、Markdown とコードは直接読み込み）
3. ユーザーが内容について質問。ユーザーが該当エントリを `shareable` にしておけば、他アプリも `library_search` 経由で同じ Library を参照可能
4. summaries → turns のカスケード検索で関連チャンクを取得
5. 取得したチャンクが LLM に渡され、それを根拠に回答が生成される

インポートしたファイルは追跡用に `~/monadic/data/library/imports/` にも保存されます。

## Monadic Help での使用 :id=use-in-monadic-help

Monadic Help アプリは同じ Qdrant + embeddings スタックを利用しますが、`help_docs` / `help_items` コレクションを参照します。これらはパッケージビルド時に事前構築されます：

1. Monadic Chat のビルド時に、ドキュメントファイルをすべて処理して埋め込みを計算
2. 結果は JSON ダンプ（`help_data/help_db.json`）として Ruby イメージに同梱される
3. 初回起動時、Monadic Chat はそのダンプを Qdrant に 1 度だけロードする
4. ユーザー質問時には、同じ query/passage 埋め込みフローで関連ドキュメントを検索
5. ヒットした内容を LLM に渡して回答を生成

埋め込み推論もストレージもローカルで完結するため、ヘルプシステムは外部プロバイダの API キーがなくても動作します。
