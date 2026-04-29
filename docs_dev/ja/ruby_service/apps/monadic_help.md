# Monadic ヘルプシステム

Monadic ヘルプシステムは、Monadic Chat ユーザー向けにドキュメントの検索と回答支援を提供します。

## アーキテクチャ

- **ストレージ**: `qdrant_service` コンテナ上の Qdrant コレクション (`help_docs`: ドキュメント単位、`help_items`: チャンク単位)
- **埋め込み**: `embeddings_service` コンテナで提供される `intfloat/multilingual-e5-base` (768 次元、L2 正規化)。外部 API キー不要。
- **ビルドパイプライン**: `rake help:build` が `docs/` 配下の Markdown を分割し (`--include-internal` 指定時は `docs_dev/` も)、JSON ダンプを `docker/services/ruby/help_data/help_db.json` に書き出します。ダンプは Ruby イメージに焼き込まれ、初回起動時に `Monadic::Help::DumpLoader` が Qdrant にインポートします。

## 機能

- **マルチチャンク検索結果**: 文脈を保つためにドキュメントごとに複数チャンクを返します。`HELP_CHUNKS_PER_RESULT` で設定可能 (デフォルト: 3)。
- **英語コーパスのみ**: ビルドスクリプトは `docs/ja`、`docs/zh`、`docs/ko` を除外します。LLM がクエリ時にユーザー言語へ翻訳することで、インデックスを小さく保ちつつ多言語アクセスを実現します。

## 設定

| 変数名 | 説明 | デフォルト |
|--------|------|------------|
| `HELP_CHUNK_SIZE` | ビルド時の Markdown チャンク文字数 | `3000` |
| `HELP_OVERLAP_SIZE` | 連続するチャンクの重複文字数 | `500` |
| `HELP_CHUNKS_PER_RESULT` | クエリ時にドキュメントごとに返すチャンク数 | `3` |
| `HELP_DATA_DUMP` | プリビルト JSON ダンプのパス (イメージ既定値を上書き) | `/monadic/help_data/help_db.json` |
| `EMBEDDINGS_URL` | embeddings サービスのベース URL を上書き | (`Monadic::Embeddings::Endpoint` が解決) |
| `QDRANT_URL` | Qdrant のベース URL を上書き | (`Monadic::VectorStore::Endpoint` が解決) |

## ヘルプ DB のビルド

```bash
# docs/* + docs_dev/* からダンプをビルド (毎回フル再構築)
rake help:build

# 既存ダンプを削除してから再構築
rake help:rebuild

# ダンプ統計を表示 (パス、埋め込みモデル、コレクション別ポイント数)
rake help:stats
```

ビルドスクリプトは常にコーパス全体を処理します — 増分スキップは行いません。ローカル CPU 上で約 150 ドキュメント (約 2,500 チャンク) を 1 分以内で埋め込めるため、簡素化を優先しています (Apple Silicon の場合)。

## 検索 API (Ruby)

- `HelpEmbeddings#find_closest_text(query, top_n:, include_internal:)` — 単チャンクヒット
- `HelpEmbeddings#find_closest_text_multi(query, chunks_per_result:, top_n:, include_internal:)` — ドキュメント単位でグループ化 (1 ドキュメントが結果を独占しない)
- `HelpEmbeddings#find_closest_doc(query, top_n:, language:)` — ドキュメント単位ヒット
- `HelpEmbeddings#search(query:, num_results:)` — MCP 互換形式 (`title` / `content` / `metadata` / `distance`)
