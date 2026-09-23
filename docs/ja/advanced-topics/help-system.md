# ヘルプシステム

Monadic Chat には、プロジェクトのドキュメントを基にした文脈対応のヘルプを提供する AI 搭載ヘルプシステムが組み込まれています。

## 概要 :id=overview

ヘルプシステムは、ローカルの sentence-transformer モデル（`multilingual-e5-base`）を使って、Monadic Chat ドキュメントから検索可能なナレッジベースを構築します。埋め込みはローカルで計算され、Qdrant に格納されます。テキストの埋め込みにもナレッジベース検索にも、外部 API キーは必要ありません。

## 機能 :id=features

- **完全ローカル検索**：埋め込み推論もベクトル格納もマシン上で完結し、ヘルプ検索のためにプロバイダ API キーは不要
- **多言語対応**：`multilingual-e5-base` は英語・日本語などを同等品質で扱える
- **マルチチャンク取得**：1 件の結果あたり複数の関連セクションを返し、包括的な回答を生成しやすくする
- **ビルド時に事前構築された JSON ダンプ**：ヘルプデータベースはパッケージビルド時に生成され、Ruby イメージに同梱され、ヘルプ検索を使うときにインストールできる
- **公開ドキュメントのみ**：出荷されるデータベースとインストール機能が扱うのは公開ドキュメントのみ

## 必要条件 :id=requirements

- 動作中の `monadic-chat-qdrant-container`（ベクトル格納）
- 動作中の `monadic-chat-embeddings-container`（multilingual-e5-base 推論）

これらは Monadic Chat 起動時に自動で立ち上がります。回答生成に使う chat モデルにはプロバイダの API キーが必要です。ヘルプデータのインストールと検索には API キーは不要です。

## 使い方 :id=usage

### ヘルプへのアクセス :id=accessing-help

1. Monadic Chat を起動し、すべてのコンテナが動作していることを確認
2. アプリメニューから「Monadic Chat Help」を選択
3. ヘルプデータのパネルで同梱データをインストール。**Monadic Chat Info → Help Data** からも API キーなしでインストール可能
4. インストール完了後、任意の言語で Monadic Chat について質問

ヘルプ検索は利用者が自分でインストールして使う機能です。Monadic Chat の起動や再ビルドでは、ヘルプデータはインストール・置換されません。パネルにインストール状態と進捗が表示されます。

同梱データが変わると、パネルに「更新があります」と表示されます。更新ボタンでインストール済みのヘルプデータを入れ替えてください。入れ替え開始までは既存のヘルプを検索できます。以前の版から利用している場合は、インストール済みデータの版を確認できないため、再インストールが必要と表示されます。

インストール・更新・再インストール・再試行の各ボタンは、確認ダイアログなしで処理を開始します。入れ替え中はヘルプ検索を利用できません。**Knowledge Base と会話ライブラリのデータは保持されます。** 失敗した場合は表示された理由を確認し、パネルからやり直してください。

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

# 開発者向け：docs_dev/* も索引化する。生成されたダンプは
# 梱包とヘルプデータのインストールで拒否される。
rake help:build_internal
```

ビルドパイプラインは、必要に応じて embeddings コンテナを起動し、ドキュメントファイルを処理して `docker/services/ruby/help_data/help_db.json` に JSON ダンプを書き出します。このダンプは Ruby Docker イメージのビルド時に組み込まれます。

## アーキテクチャ :id=architecture

### 格納 :id=storage

ヘルプデータはローカルの Qdrant に、Knowledge Base や会話ライブラリのデータと分けて格納されます。文書全体とその断片を索引化し、検索時に関連するセクションを返します。ヘルプデータの更新で入れ替わるのはヘルプの索引だけです。

### ビルド時パイプライン :id=build-time-pipeline

1. **ドキュメント処理**：
   - `rake help:build` が `scripts/utilities/process_documentation.rb` を実行
   - Markdown を既定でチャンクサイズ 3000 文字、オーバーラップ 500 文字で分割
   - 階層的な見出しパスを各断片とともに保存

2. **埋め込み生成**：
   - 各チャンクは「passage」として embeddings コンテナへ送信
   - サービス側で e5 の `passage:` プレフィックスを付与し、L2 正規化済みの 768 次元ベクトルを返す
   - ドキュメントごとに、その断片の埋め込み平均もベクトルとして作成

3. **JSON ダンプの書き出し**：
   - 処理結果を `docker/services/ruby/help_data/help_db.json` に書き出し
   - Ruby Docker イメージのビルド時にダンプを焼き込み

### 実行時パイプライン :id=runtime-pipeline

1. **インストール**：
   - 利用者が Help アプリのパネルまたは **Monadic Chat Info → Help Data** から開始
   - Monadic Chat が同梱データを検証し、以前のヘルプ索引を置換して結果を確認
   - 完了後に検索が利用可能となり、以降の起動ではインストール済みデータを使用
   - 新しい同梱版は更新として案内され、反映には明示的なインストール操作が必要

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

- `HELP_DATA_DUMP`：インストール操作で使う JSON ダンプのパスを上書き（既定：Ruby コンテナ内の `/monadic/help_data/help_db.json`）。パスの変更だけでは自動インストールされない

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
3. 新しいダンプを使うよう Ruby コンテナを再ビルドし、作り直す
4. Help アプリのパネルまたは **Monadic Chat Info → Help Data** を開き、ヘルプデータをインストールまたは更新

再ビルドだけでは稼働中のヘルプデータベースは変わりません。`docs_dev/` 以下の内部ノートは出荷されるデータベースには含まれません。`rake help:build_internal` は開発用ダンプを生成しますが、内部コンテンツは梱包時にもヘルプデータのインストール時にも拒否されます。`DEBUG_MODE=true` でも同じです。

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

- 回答生成に使う chat モデルにはプロバイダの API キーが必要。インストールと検索には API キーは不要
- 言語によりカバレッジ・精度は異なる（spaCy / sentence-transformer は言語ごとに異なるコーパスで学習）

## トラブルシューティング :id=troubleshooting

### よくある問題 :id=common-issues

1. **ヘルプ検索を利用できない、または結果を返さない**
   - Help アプリのパネルまたは **Monadic Chat Info → Help Data** で状態を確認し、案内に従ってインストールまたは再インストール
   - インストール中なら完了を待つ。失敗したら表示された理由を確認して再試行
   - 両コンテナの動作を確認：`docker ps | grep -E 'qdrant|embeddings'`

2. **検索結果が貧弱**
   - ヘルプデータの更新があればインストール
   - ドキュメント自体に十分な記述があるか確認
   - ドキュメント開発者はチャンクサイズを調整し、`rake help:rebuild` でダンプを再生成して、[ドキュメントの追加](#adding-documentation) の手順でインストール

3. **ビルドが "embeddings_service did not become ready" で失敗**
   - embeddings イメージが build されているか確認：`docker images | grep monadic-embeddings`
   - コンテナログを確認：`docker logs monadic-chat-embeddings-container`
   - モデルのロード完了を待ってからビルドを再試行

4. **アップグレード後にヘルプデータの操作を求められる**
   - Help アプリのパネルまたは **Monadic Chat Info → Help Data** を開く
   - 未インストールならインストール、更新があれば更新、以前の版を確認できない場合は再インストール
   - コンテナの再起動や再ビルドではヘルプデータは入れ替わらないため、パネルから操作
