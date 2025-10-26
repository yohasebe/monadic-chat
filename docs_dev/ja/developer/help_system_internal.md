# Monadic Helpの内部ドキュメントサポート

## 概要

Monadic Helpシステムは、`is_internal`フラグを通じて外部（公開）および内部（開発者専用）ドキュメントの両方をサポートします。この機能により、開発者は開発中に公開ユーザードキュメント（`docs/`）と並行して内部技術ドキュメント（`docs_dev/`）を検索できますが、内部ドキュメントが配布パッケージに含まれないことを保証します。

## アーキテクチャ

### データベーススキーマ

`help_docs`と`help_items`の両テーブルに`is_internal`ブール列が含まれます：

```sql
CREATE TABLE help_docs (
  ...
  is_internal BOOLEAN DEFAULT FALSE,
  ...
);

CREATE TABLE help_items (
  ...
  is_internal BOOLEAN DEFAULT FALSE,
  ...
);

-- 効率的なフィルタリングのためのインデックス
CREATE INDEX idx_help_docs_is_internal ON help_docs(is_internal);
CREATE INDEX idx_help_items_is_internal ON help_items(is_internal);
```

### データフロー

```
┌─────────────────────────────────────────────────────┐
│ 開発（DEBUG_MODE=true）                             │
├─────────────────────────────────────────────────────┤
│ docs/（45ファイル） → is_internal=false            │
│ docs_dev/（154ファイル） → is_internal=true        │
│                                                      │
│ データベース：合計199ドキュメント                   │
│ 検索：外部 + 内部の両方を返す                       │
│ エクスポート：N/A（DEBUG_MODEではエクスポートなし） │
└─────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────┐
│ 本番（rake build）                                   │
├─────────────────────────────────────────────────────┤
│ docs/（45ファイル） → is_internal=false            │
│                                                      │
│ データベース：外部ドキュメントのみ45件              │
│ 検索：外部ドキュメントのみを返す                    │
│ エクスポート：is_internal=falseエントリのみ         │
└─────────────────────────────────────────────────────┘
```

## 使用方法

### 開発者向け

#### 1. 内部ドキュメント付きヘルプデータベースのビルド

```bash
# オプション1：DEBUG_MODEを使用（自動）
rake server:debug  # 内部ドキュメントを自動的に含める

# オプション2：明示的ビルド
rake help:build_dev
```

#### 2. 内部ドキュメントの検索

`DEBUG_MODE=true`が設定されている場合、Monadic Helpは検索結果に内部ドキュメントを自動的に含めます：

```ruby
# Monadic Helpアプリ内
find_help_topics(text: "model spec vocabulary")
# docs/とdocs_dev/の両方から結果を返す

# Rubyコード内
help_db.find_closest_text("SSOT pattern", include_internal: true)
```

#### 3. 内部ドキュメントが読み込まれていることを確認

```bash
# ヘルプデータベースに接続
docker exec -it monadic-chat-pgvector-container psql -U postgres -d monadic_help

# ドキュメント数を確認
SELECT is_internal, COUNT(*) FROM help_docs GROUP BY is_internal;

# 期待される出力：
#  is_internal | count
# -------------+-------
#  f           |    45  -- 外部ドキュメント
#  t           |   154  -- 内部ドキュメント
```

### 配布向け

#### パッケージのビルド

```bash
# 標準ビルド（外部ドキュメントのみ）
rake build

# 内部ドキュメントを明示的にスキップ
SKIP_INTERNAL_DOCS=true rake build
```

ビルドプロセス：
1. `docs/`ディレクトリのみを処理（45ファイル）
2. `is_internal=false`エントリのみをエクスポート
3. パッケージに内部ドキュメントは含まれない
4. ファイルサイズは最小限に保たれる

#### エクスポートコンテンツの検証

```bash
# エクスポートされたファイルを確認
cat docker/services/pgvector/help_data/metadata.json

# エクスポートに内部ドキュメントがないことを確認
docker exec -it monadic-chat-pgvector-container \
  psql -U postgres -d monadic_help \
  -c "SELECT COUNT(*) FROM help_docs WHERE is_internal = TRUE;"
# エクスポートされたデータベースでは0を返すはず
```

## 実装詳細

### ProcessDocumentation

ドキュメントプロセッサーは`include_internal`パラメーターを受け入れます：

```ruby
class ProcessDocumentation
  DOCS_PATH = ".../docs"
  DOCS_DEV_PATH = ".../docs_dev"  # 追加

  def process_all_docs(include_internal: false)
    # DEBUG_MOードを自動検出
    include_internal ||= (ENV['DEBUG_MODE'] == 'true')

    # 常に外部ドキュメントを処理
    process_language_docs("en", DOCS_PATH, is_internal: false)

    # 条件付きで内部ドキュメントを処理
    if include_internal
      process_language_docs("en", DOCS_DEV_PATH, is_internal: true)
    end
  end
end
```

### 検索フィルタリング

すべての検索メソッドは`DEBUG_MODE`を自動検出します：

```ruby
module MonadicHelpTools
  def find_help_topics(text:, include_internal: nil)
    # 明示的に指定されていない場合は自動検出
    include_internal = (ENV['DEBUG_MODE'] == 'true') if include_internal.nil?

    results = help_embeddings_db.find_closest_text_multi(
      text,
      include_internal: include_internal
    )
  end
end

class HelpEmbeddings
  def find_closest_text(text, include_internal: false)
    where_clause = include_internal ? "" : "WHERE hi.is_internal = FALSE"

    conn.exec_params(<<~SQL, [embedding, top_n])
      SELECT hi.*, hd.*
      FROM help_items hi
      JOIN help_docs hd ON hi.doc_id = hd.id
      #{where_clause}
      ORDER BY hi.embedding <=> $1::vector
      LIMIT $2
    SQL
  end
end
```

### エクスポートプロセス

エクスポートスクリプトは内部ドキュメントを明示的にフィルタリングします：

```ruby
class HelpDatabaseExporter
  def export_data
    # 外部ドキュメントのみをエクスポート
    docs = conn.exec("SELECT * FROM help_docs WHERE is_internal = FALSE")

    # 外部ドキュメントのアイテムのみをエクスポート
    items = conn.exec(<<~SQL)
      SELECT hi.* FROM help_items hi
      JOIN help_docs hd ON hi.doc_id = hd.id
      WHERE hd.is_internal = FALSE
    SQL
  end
end
```

## Rakeタスク

### help:build
- **目的**：外部ドキュメントのみをビルド
- **使用法**：`rake help:build`
- **動作**：
  - `docs/`ディレクトリを処理
  - すべてのエントリに`is_internal=false`を設定
  - ビルド後に自動的にエクスポート
  - パッケージ作成のために`rake build`で使用

### help:build_dev
- **目的**：開発用に外部 + 内部ドキュメントをビルド
- **使用法**：`rake help:build_dev`
- **動作**：
  - `docs/`と`docs_dev/`の両方を処理
  - `docs_dev/`エントリに`is_internal=true`を設定
  - エクスポートしない（内部ドキュメントはローカルに留まる）
  - `rake server:debug`によって自動的に呼び出される

### help:export
- **目的**：配布用にヘルプデータベースをエクスポート
- **使用法**：`rake help:export`
- **動作**：
  - `is_internal=false`エントリのみをエクスポート
  - `is_internal`列を持つschema.sqlを作成
  - help_docs.jsonとhelp_items.jsonを生成
  - `rake help:build`によって自動的に呼び出される

## パフォーマンス考慮事項

### データベースサイズ

- **外部のみ**：約45ドキュメント、約500-1000アイテム
- **外部 + 内部**：約199ドキュメント、約2000-4000アイテム（**4倍増加**）

### ビルド時間

- **外部のみ**（`rake build`）：約2-5分
- **外部 + 内部**（`rake help:build_dev`）：約8-15分（**3-4倍遅い**）

### 検索パフォーマンス

`is_internal`のインデックスにより、フィルタリングのパフォーマンス影響を最小限に抑えます：

```sql
-- インデックスを使用した高速クエリ
SELECT * FROM help_docs WHERE is_internal = FALSE;
-- idx_help_docs_is_internalを使用
```

## セキュリティ考慮事項

### 配布されるもの

✅ **パッケージに含まれる：**
- `docs/`ディレクトリ（外部ドキュメント）
- `is_internal=false`のみでエクスポートされたデータベース

❌ **パッケージに含まれない：**
- `docs_dev/`ディレクトリ
- `is_internal=true`のデータベースエントリ
- 開発者ノート、TODO、実装詳細

### 検証

リリース前に確認：

```bash
# 1. エクスポートファイルサイズを確認（約1-5MBであるべき、10-20MBではない）
ls -lh docker/services/pgvector/help_data/*.json

# 2. エクスポートコンテンツを確認
jq '. | length' docker/services/pgvector/help_data/help_docs.json
# 約45を表示すべき、約199ではない

# 3. エクスポートに内部フラグがないことを確認
jq '.[].is_internal' docker/services/pgvector/help_data/help_docs.json | sort -u
# 'false'またはnullのみを表示すべき、決して'true'ではない
```

## トラブルシューティング

### 検索に内部ドキュメントが表示されない

**症状**：Monadic Helpが外部ドキュメントのみを返す

**解決策**：
1. DEBUG_MODEが設定されているか確認：`echo $DEBUG_MODE`（`true`であるべき）
2. 内部ドキュメントがデータベースにあるか確認：
   ```sql
   SELECT COUNT(*) FROM help_docs WHERE is_internal = TRUE;
   ```
3. ヘルプデータベースを再ビルド：`rake help:build_dev`

### 本番環境に内部ドキュメントが表示される

**症状**：ユーザーが開発者ドキュメントを見たと報告

**解決策**：
1. エクスポートファイルを確認：`grep is_internal docker/services/pgvector/help_data/*.json`
2. エクスポートを再ビルド：`rake help:build`（`help:build_dev`ではない）
3. 本番環境に`DEBUG_MODE`がないことを確認

### ビルド時間が長すぎる

**症状**：`rake build`が15分以上かかる

**解決策**：
1. `docs_dev/`が処理されているか確認（処理されるべきではない）
2. `SKIP_HELP_DB=true rake build`を使用してヘルプDBを完全にスキップ
3. ビルドプロセスで`include_internal: false`を確認

## ベストプラクティス

### 開発者向け

1. **開発には`rake server:debug`を使用** - 内部ドキュメントを自動的に含める
2. **内部ドキュメントを整理して保持** - `docs_dev/`で明確なファイル構造を使用
3. **内部機能をドキュメント化** - 技術実装ノートを`docs_dev/developer/`に追加

### メンテナー向け

1. **リリースには常に`rake build`を使用** - パッケージに`help:build_dev`を使用しない
2. **エクスポートコンテンツを検証** - リリース前にファイルサイズと`is_internal`フラグを確認
3. **docs_dev/を.gitignoreに入れない** - 内部ドキュメントはバージョン管理すべき
4. **内部ドキュメントを定期的にレビュー** - 古いTODOと一時的なノートを削除

### ドキュメント用

1. **外部ドキュメント（`docs/`）**：エンドユーザー機能、安定したAPI、使用ガイド
2. **内部ドキュメント（`docs_dev/`）**：実装詳細、アーキテクチャ決定、開発ワークフロー
3. **一時的なノート（`tmp/memo/`）**：WIPアイテム、未解決の問題（ヘルプシステムにはない）

## 参照

- [ヘルプシステムドキュメント](../../docs/advanced-topics/help-system.md) - 公開ドキュメント
- [ProcessDocumentationソース](../../docker/services/ruby/scripts/utilities/process_documentation.rb)
- [HelpEmbeddingsソース](../../docker/services/ruby/lib/monadic/utils/help_embeddings.rb)
- [エクスポートスクリプトソース](../../docker/services/ruby/scripts/utilities/export_help_database_docker.rb)
