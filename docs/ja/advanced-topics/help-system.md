# ヘルプシステム

Monadic Chatには、プロジェクトのドキュメントに基づいて文脈に応じた支援を提供するAI駆動のヘルプシステムが含まれています。

## 概要 :id=overview

ヘルプシステムは、OpenAIのエンベディングを使用してMonadic Chatのドキュメントから検索可能なナレッジベースを作成します。これにより、インテリジェントで文脈に応じた応答が可能になります。

## 機能 :id=features

- **自動言語検出**：英語のドキュメントのみを保存しながら、ユーザーの言語で応答
- **マルチチャンク検索**：包括的な回答のために複数の関連セクションを返す
- **増分更新**：MD5ハッシュ追跡を使用して変更されたドキュメントファイルのみを処理
- **バッチ処理**：より良いパフォーマンスのために効率的にエンベディングをバッチで処理
- **自動コンテナ再構築**：ヘルプデータが更新されるとPGVectorコンテナが自動的に再構築

## 必要条件 :id=requirements

- OpenAI APIキー（エンベディングとチャット機能用）
- 実行中のpgvectorコンテナ

## 使用方法 :id=usage

### ヘルプへのアクセス :id=accessing-help

1. Monadic Chatを起動し、すべてのコンテナが実行中であることを確認
2. アプリメニューから「Monadic Chat Help」を選択
3. 任意の言語でMonadic Chatについて質問


### よくある質問 :id=common-questions

- 「グラフを生成するには？」→ Math TutorまたはMermaid Grapherアプリを提案
- 「PDFで作業するには？」→ PDF Navigatorアプリを説明
- 「どのような音声機能がありますか？」→ Voice Chatと音声合成オプションを説明

## ヘルプデータベースの構築 :id=building-help-database

ヘルプデータベースは開発中にドキュメントから構築されます：

```bash
# ヘルプデータベースを構築（増分更新）
rake help:build

# 最初から再構築
rake help:rebuild

# 統計を表示
rake help:stats

# 配布用にデータベースをエクスポート
rake help:export
```


## 設定 :id=configuration

### 設定変数 :id=configuration-variables

- `HELP_CHUNK_SIZE`：チャンクあたりの文字数（デフォルト：3000）
  - 処理中にドキュメントがどのように分割されるかを制御
  - 大きい値はより多くのコンテキストを保持

- `HELP_OVERLAP_SIZE`：チャンク間の文字の重複（デフォルト：500）
  - チャンク間のコンテキストの連続性を維持
  - 推奨：チャンクサイズの15-20％

- `HELP_EMBEDDINGS_BATCH_SIZE`：APIコールのバッチサイズ（デフォルト：50、最大：2048）
  - 大きいバッチはより効率的だがタイムアウトする可能性
  - APIの制限に基づいて調整

- `HELP_CHUNKS_PER_RESULT`：結果あたりに返されるチャンク数（デフォルト：3）
  - より多くのチャンクはより良いコンテキストを提供
  - 応答の品質と完全性に影響

### 設定例 :id=example-configuration

`~/monadic/config/env`ファイルにこれらの設定を追加します：

```
HELP_CHUNK_SIZE=4000
HELP_OVERLAP_SIZE=800
HELP_EMBEDDINGS_BATCH_SIZE=100
HELP_CHUNKS_PER_RESULT=5
```

## アーキテクチャ :id=architecture

### データベース構造 :id=database-structure

ヘルプシステムは、pgvector拡張機能を持つ別個のPostgreSQLデータベース（`monadic_help`）を使用します：

- `help_docs`：ドキュメントのメタデータとエンベディングを保存
  - title、file_path、section、language
  - 初期フィルタリング用のドキュメントレベルのエンベディング
  - (file_path, language)に対する一意制約

- `help_items`：エンベディングを持つ個々のテキストチャンクを保存
  - テキストコンテンツ、位置、見出し情報
  - 詳細検索用のチャンクレベルのエンベディング
  - 外部キーを介して親ドキュメントにリンク

### エクスポート/インポートプロセス :id=export-import-process

1. **開発フェーズ**：
   - `rake help:build`を使用してドキュメントが処理される
   - OpenAI APIを介してエンベディングが生成される
   - ビルド/再構築後にデータベースが自動的にエクスポートされる

2. **配布**：
   - エクスポートファイルは`docker/services/pgvector/help_data/`に保存
   - ファイルには以下が含まれる：schema.sql、help_docs.json、help_items.json、metadata.json
   - エクスポートIDが自動再構築のためのバージョンを追跡

3. **ユーザーインストール**：
   - PGVectorコンテナが初回実行時にデータをインポート
   - インポートスクリプトがJSONからPostgreSQLへの変換を処理
   - エンベディングがエクスポートファイルから復元される

### 自動コンテナ再構築 :id=automatic-container-rebuilding

システムはエクスポートIDを使用してヘルプデータベースの更新を追跡します：

1. ヘルプデータベースが再構築されると、新しいエクスポートIDが生成される
2. IDは`help_data/export_id.txt`に保存される
3. 起動時に、monadic.shは保存されたIDとコンテナIDを比較
4. 異なる場合、PGVectorコンテナが自動的に再構築される
5. コンテナの初期化中に新しいヘルプデータがインポートされる

## 設定変数 :id=configuration-variables

ヘルプシステムは`~/monadic/config/env`の環境変数で設定できます：

### ヘルプシステム設定

- `HELP_CHUNK_SIZE`: チャンクあたりの文字数（デフォルト：3000）
  - ドキュメントの処理時の分割方法を制御
  - 大きいチャンクはより多くのコンテキストを提供しますが、検索精度が低下する可能性があります
  
- `HELP_OVERLAP_SIZE`: チャンク間でオーバーラップする文字数（デフォルト：500）
  - 隣接するチャンク間の連続性を提供
  - チャンク境界でのコンテキスト損失を防ぎます

- `HELP_EMBEDDINGS_BATCH_SIZE`: API呼び出しのバッチサイズ（デフォルト：50）
  - 単一のOpenAI API呼び出しで処理されるチャンク数
  - APIレート制限に基づいて調整

- `HELP_CHUNKS_PER_RESULT`: 検索結果ごとに返されるチャンク数（デフォルト：3）
  - 各検索結果に含まれる関連チャンクの数
  - 高い値はより多くのコンテキストを提供

設定例：
```
HELP_CHUNK_SIZE=4000
HELP_OVERLAP_SIZE=600
HELP_EMBEDDINGS_BATCH_SIZE=25
HELP_CHUNKS_PER_RESULT=5
```

## 開発 :id=development

### ドキュメントの追加 :id=adding-documentation

1. `docs/`ディレクトリにマークダウンファイルを追加または変更
2. `rake help:build`を実行してデータベースを更新
3. システムは変更されたファイルのみを処理

### 処理の詳細 :id=processing-details

- **増分更新**：MD5ハッシングが変更されたドキュメントを検出
- **バッチ処理**：設定可能なバッチでエンベディングを処理
- **多言語**：`/ja/`および他の言語ディレクトリを除外
- **階層的コンテキスト**：メタデータに見出し構造を保持

### テスト :id=testing

ヘルプシステムをテストするには：

```bash
# クリーン再構築
rake help:rebuild

# 統計を確認
rake help:stats

# アプリでテスト
# 1. サーバーを起動
# 2. Monadic Chat Helpを開く
# 3. 異なる言語でクエリをテスト
```


### デバッグ :id=debugging

デバッグ出力を有効にする：

1. `~/monadic/config/env`ファイルに以下を追加：
```
EMBEDDINGS_DEBUG=true
HELP_EMBEDDINGS_DEBUG=1
```

2. ヘルプデータベースをビルド：
```bash
rake help:build
```

## パフォーマンスの最適化 :id=performance-optimization

### チャンクサイズのガイドライン :id=chunk-size-guidelines

- **技術文書**：コード例を保持するために大きいチャンク（4000-5000）を使用
- **FAQ/短いコンテンツ**：正確なマッチングのために小さいチャンク（2000-3000）を使用
- **一般的なコンテンツ**：デフォルト（3000）がほとんどの場合によく機能

### APIパフォーマンス :id=api-performance

- タイムアウトが発生する場合は`HELP_EMBEDDINGS_BATCH_SIZE`を減らす
- OpenAI APIのレート制限を監視
- オフピーク時間での処理を検討

### 検索品質 :id=search-quality

- 回答が不完全な場合は`HELP_CHUNKS_PER_RESULT`を増やす
- より多くの結果を得るために検索呼び出しの`top_n`パラメータを調整
- より良いマッチングのために特定の検索用語を使用

## 制限事項 :id=limitations

- OpenAI APIキーが必要（他のエンベディングプロバイダーのサポートなし）
- 英語のドキュメントのみ（応答は機械翻訳）
- モデルの制約により最大コンテキストが制限
- エンベディング次元は3072に固定（OpenAI text-embedding-3-large）

## トラブルシューティング :id=troubleshooting

### よくある問題 :id=common-issues

1. **「ヘルプデータベースが存在しません」**
   - `rake help:build`を実行してデータベースを作成
   - pgvectorコンテナが実行中であることを確認

2. **検索結果が悪い**
   - より良いコンテキストのためにチャンクサイズを増やす
   - `rake help:rebuild`でデータベースを再構築
   - ドキュメントに十分な詳細があるか確認

3. **エクスポートの失敗**
   - pgvectorコンテナが実行中であることを確認
   - エクスポートファイル用のディスク容量を確認
   - データベース接続設定を確認

4. **インポートの失敗**
   - pgvectorコンテナのログを確認
   - エクスポートファイルが有効なJSONであることを確認
   - コンテナにPythonとpsycopg2がインストールされていることを確認

5. **パッケージアプリのパス関連の問題**
   - ヘルプシステムスクリプトは相対パスを使用します
   - スクリプトは正しいベースディレクトリを自動的に検出します
   - インポートが失敗した場合は、`docker/services/pgvector/help_data/`にエクスポートファイルが存在することを確認してください

6. **新しいコンテナでヘルプデータベースが読み込まれない**
   - 症状: Monadic Helpアプリのfunction callingが停止し、レスポンスが返ってこない
   - データの存在確認: `docker exec monadic-chat-pgvector-container psql -U postgres -d monadic_help -c "SELECT COUNT(*) FROM help_items"`
   - 一般的な原因:
     - コンテナ初期化中にPostgreSQLの初期化スクリプトが失敗
     - 起動時にPython psycopg2がlocalhostに接続できない
   - システムはPostgreSQLの準備完了後にインポートを実行するカスタムエントリーポイントスクリプトを使用しています
   - 自動インポートが失敗してもコンテナは実行を継続し、help:build rakeタスクを使用できます