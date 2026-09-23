# ヘルプデータベース内の内部ドキュメント

## 概要

ヘルプのデータ形式は、公開ドキュメント（`docs/`）と開発者向け内部
ドキュメント（`docs_dev/`）の両方に対応します。各ポイントには `is_internal`
payload が付きます。読取 API は既定で内部ポイントを除外し、インストール機能は
明示的に公開と指定されたポイントだけを受け入れます。

出荷されるデータベースに入るのは**公開ドキュメントだけ**です（`docs/` と、
ルートの `README.md`・`CHANGELOG.md`）。`rake help:build` は `--public-only` を
渡し、`HelpDumpGuard` が内部ポイントを含むダンプの梱包を拒否します。拒否は
`scripts/stage_docker_payload.rb` と、npm のビルドスクリプトが通る `beforePack`
フックの両方から効きます。開発者は `rake help:build_internal` で `docs_dev/` を
含むダンプを生成できますが、梱包ゲートと `Monadic::Help::ValidatedDump` の
両方が拒否します。`DEBUG_MODE=true` でも、ヘルプデータのインストール機能では
このダンプを導入できません。

## アーキテクチャ

### ストレージ

ヘルプインデックスは2つの Qdrant コレクションに入ります
（`lib/monadic/vector_store/schema.rb`）。

- `help_docs` — ドキュメントファイル1件につき1ポイント
- `help_items` — チャンク化された断片1つにつき1ポイント

どちらも payload に `is_internal` を持ちます。ベクトルは768次元・コサイン距離です。

### ビルド

`scripts/utilities/process_documentation.rb` が両方のツリーを走査します。

```ruby
process_language_docs('en', DOCS_PATH, is_internal: false)      # docs/
if include_internal && Dir.exist?(DOCS_DEV_PATH)
  process_language_docs('en', DOCS_DEV_PATH, is_internal: true) # docs_dev/
end
```

`include_internal` は3つの入力から、次の優先順位で決まります。

```ruby
include_internal = false if public_only
include_internal ||= (ENV['DEBUG_MODE'] == 'true') unless public_only
```

`--public-only` がすべてに優先します。開発用シェルでは `DEBUG_MODE` が設定
されていることが普通なので、明示的な上書きがないと、そこから走らせた出荷
ビルドが黙って内部込みのダンプを作ってしまうためです。`--include-internal` を
外すだけでは足りません。

ダンプはどちらで生成されたかをメタデータに記録するので、全ポイントを走査せず
に確認できます。

```json
{ "includes_internal": false }
```

結果は `docker/services/ruby/help_data/help_db.json` に書き出され、Ruby イメージ
がこれを焼き込みます（`Dockerfile` の `COPY help_data/`）。

### 検索

`HelpEmbeddings` の全コンテンツ読取 API は `include_internal: false` が既定です。
対象は `find_closest_text`、`find_closest_text_multi`、`find_closest_doc`、
`list_titles`、`get_text_snippets`、`search`、`get_stats`、`get_unique_categories`、
`get_by_category` です。`is_internal == false` を要求するため、内部ポイントだけで
なくフラグのないポイントも除外します。可視性フィルタは言語・文書・カテゴリの
フィルタと組み合わせます。アイテムの結果と統計は親文書の可視性にも従います。

例えば `find_closest_text` は Qdrant の payload フィルタを適用します。

```ruby
def find_closest_text(text, top_n: 10, include_internal: false)
  filter = include_internal ? nil : without_internal_filter
  ...
end

def without_internal_filter
  { must: [{ key: 'is_internal', match: { value: false } }] }
end
```

フラグはリクエストごとに Monadic Help アプリが決めます
（`apps/monadic_help/monadic_help_tools.rb`）。

```ruby
include_internal = (ENV['DEBUG_MODE'] == 'true') if include_internal.nil?
```

`DEBUG_MODE` が参照されるのは呼び出し側が何も渡さなかったときだけで、明示的な
`include_internal:` が優先されます。これは既存データの可視性だけを制御し、
内部文書をインストールするものではありません。公開ダンプには内部ポイントが
なく、インストーラーは `DEBUG_MODE` にかかわらず内部ダンプを拒否します。

すべての Help ツールは、埋め込み、アイテム取得、親文書取得を含む読取処理全体を
`Monadic::Help.installation.with_search` 内で実行します。渡された接続をブロックの
外へ持ち出してはいけません。検索不可の場合、ツールはコレクションの作成やデータの
取り込みを行わず、構造化されたインストール案内を返します。

## Rake タスク

`rakelib/help.rake` で定義されています。

### help:build
`--public-only` を渡し、公開ドキュメントだけからダンプを再生成します。出荷
ビルドが走らせるのはこちらです。ポート 8002 に到達できなければ embeddings
コンテナを起動し、**このタスクが起動した場合にかぎり**終了後に停止します
（`KEEP_VECTOR_SERVICES=true` のときは停止しません）。

### help:build_internal
同じですが `--include-internal` を渡すので `docs_dev/` も対象になります。
手元の開発用のみ。生成されたダンプは梱包時とヘルプデータのインストール時に拒否されます。

### help:rebuild
既存のダンプを削除してから同じビルドを実行します。

### help:stats
現在のダンプの統計を表示します。

### help:export
ダンプのパスを表示し、ファイルがなければ非ゼロで終了します。変換やフィルタは
行いません。

### help:build_dev
非推奨。警告を出して `help:build_internal` にリダイレクトします。

## 配布

ダンプは2つの経路で利用者に届き、どちらもファイルをそのまま扱います。

- `scripts/stage_docker_payload.rb` が `REQUIRED_BUILD_PRODUCTS` に
  `help_data/help_db.json` を列挙し、Electron パッケージへ staging します。
- Ruby イメージがビルド時に `help_data/` をコピーします。

`rakelib/build.rake` は `SKIP_HELP_DB=true` のとき再生成を省略するため、その場合は
ディスク上にあるダンプがそのまま出荷されます。梱包ゲートが守っているのはこの
ケースです。規則は `scripts/help_dump_guard.rb` が持ち、梱包の経路が2つあるため
2箇所から呼ばれます。

- `scripts/stage_docker_payload.rb` は staging 前にソースツリーのダンプを検査
  します。Rake 経路がこちらです。
- electron-builder の `beforePack` に登録した `scripts/before_pack.js` は、
  `build/app-payload/` 配下の **staging 済み**のコピーを検査します。npm の
  ビルドスクリプト（`npm run build:mac-arm64` など）は electron-builder を直接
  起動し stager を呼ばないため、このフックがないと以前 staging された内容を、
  あるいは何も梱包しないまま通してしまいます。app-builder-lib は
  `extraResources` のコピー元が無いとき `file source doesn't exist` を警告する
  だけだからです。したがって staging 済みダンプが無い場合もビルドを失敗させ、
  ヘルプデータベースを欠いたインストーラを作らないようにしています。

ゲートが拒否するのは、`is_internal` のポイントを含むダンプ、ツリーに存在しない
ファイルを出所として持つダンプ、そして形式が読み取れないダンプです。空の
コレクションや、id・payload ハッシュ・真偽値の `is_internal` を備えていない
ポイントがこれにあたります。読み取れないポイントは出荷可否を判断できない
ポイントなので、読み飛ばさずに拒否します。
`help:build_internal` を走らせた後に `SKIP_HELP_DB=true` で梱包した開発者は、
内部ダンプを出荷する前に止められます。

### 既存インストールへの読み込み

`Monadic::Help::Installation` は、利用者の明示的な操作でのみデータをインストール
します。起動時のローダーは取り込みもコレクションの初期作成も行いません。
入口は Monadic Chat Help のパネルと **Monadic Chat Info → Help Data** です。
状態表示にもインストールにもプロバイダの API キーは不要です。

- `GET /help/database` は独立したパネルを表示します。
- `GET /help/database/status` は読取専用の状態を返し、ロックファイルや
  コレクションを作りません。
- `POST /help/database/install` はバックグラウンド処理を開始し、HTTP 202 と
  `install_id` を返します。ロックが使用中なら HTTP 409 と `retryable: true` を
  返すので、呼び出し側が明示的に再試行します。パラメータ付きリクエストは
  HTTP 400、別オリジンからのリクエストは HTTP 403 で拒否します。

このエンドポイントは、同じダンプがインストール済みでも明示的なインストールを
受け付け、データを再度入れ替えます。確認ダイアログは要求しません。

#### インストール状態

| 状態 | 意味 | 検索可否 |
|---|---|---|
| `not_installed` | 両方のヘルプコレクションがなく、失敗したインストール試行もない | 不可 |
| `legacy` | 両方のヘルプコレクションはあるが、いずれにもインストール記録がない。版を検証するため再インストールが必要 | 不可 |
| `installing` | インストール処理がジョブロックを保持中 | 状態応答では不可 |
| `installed` | 一致する完了記録と正確な件数を検証済み | 可 |
| `update_available` | インストール済みデータは検証済みだが、SHA-256 が同梱ファイルと異なる | 入れ替え開始まで可 |
| `failed` | 使用可能な DB を残さずインストールが失敗、または記録・件数の欠落、不一致、未完了 | 不可 |
| `unavailable` | ベクトルストアへの接続または問い合わせに失敗 | 不可 |

同梱ファイルの指紋を取得できなくても、検証済みのインストール済み DB は検索可能です。
その場合 `bundled_match` は `null` となり、`bundled_error` に理由が入ります。
検証段階で失敗した場合も、それ以前の正常な DB は保持され、失敗した試行は
`last_attempt` に記録されます。

#### 排他と入れ替え

同じ DB を扱うインスタンスとプロセスは、調整用ディレクトリを共有する必要が
あります。コンテナ内は `/monadic/data/.help-installation`、ホスト上は
`~/monadic/data/.help-installation` です。`job.lock` がインストール処理を直列化し、
`readers.lock` が `flock` で Help の読取処理全体を保護します。ロックの所有権は
inode に結び付くため、ロックファイルを削除してはいけません。進捗はファイルと
ディレクトリの `fsync` およびアトミックな rename で `progress.json` に永続化します。

処理順序は次のとおりです。

1. **検証**：DB を変更する前に `ValidatedDump` がダンプ全体を検証します。
   形式の版、埋め込みモデルと次元、必要な 2 コレクション、一意な符号なし整数 ID、
   明示的に公開とされた payload、有限値のベクトル、アイテムから文書への参照を
   検査します。SHA-256 と投入ポイントは同じファイル読み込みから取得します。
   この段階では状態応答は `installing` ですが、正常な既存データは `with_search`
   で引き続き読めます。
2. **準備**：新しい検索を受け付けず、実行中の読取処理の完了を待ちます。
   最初の破壊的変更より前に `database_invalid: true` を永続化します。
3. **置換**：`help_docs` と `help_items` だけを対象に、各コレクションを削除・
   再作成し、`state: installing` のインストールメタデータを付けます。
   `library_*` と `pdf_*` は変更しません。
4. **投入**：ポイントをバッチ投入します。各 upsert が `completed` を返したことを
   確認してから進捗を進めます。
5. **件数確認**：両コレクションの正確な件数をダンプと照合します。
6. **完了記録**：両コレクションに `state: completed` と `loaded_at` を書きます。
   記録を読み戻して意図した内容との一致を検証し、**正確な件数を再度確認**します。
7. **終了**：完了状態と `database_invalid: false` を進捗ファイルに永続化し、
   ロックを解放して検索を再開できるようにします。

入れ替えに失敗した場合や途中で中断された場合は、明示的な再試行が完了するまで
検索不可です。自動ロールバックや自動再試行はありません。永続化した無効状態により、
両方の完了記録を書いた後、最終検証前に中断した場合も保護します。ジョブロックが
解放されているのに実行中の進捗記録が残っていれば、失敗した試行として報告します。

#### インストールメタデータと新しいダンプ

両コレクションは `monadic_help_installation` キーに同じ記録を持ちます。

- `install_id`、`dump_sha256`、`dump_version`
- `embedding_model`、`embedding_dimension`
- `expected_docs`、`expected_items`
- `state`、`loaded_at`、`exported_at`（ダンプの書き出し時刻）

版は `1`、モデルは `intfloat/multilingual-e5-base`、ベクトル次元は 768 です。
利用可能と判定するには、互換性のある完了記録の一致と正確な件数が必要です。
`exported_at` は参考情報です。インストール済みの SHA-256 と現在のダンプを比較し、
更新の有無を判定します。

公開文書の変更を届けるには `rake help:build` を実行し、新しいダンプを含むよう
Ruby コンテナを再ビルドして作り直すか、読み取り可能なダンプをマウントして
`HELP_DATA_DUMP` で指定します。その後、パネルでインストールまたは更新します。
再ビルド・再起動・パス変更だけではインストール済みデータは置換されません。
Qdrant のボリュームには利用者のデータも含まれるため、全体を削除しないでください。

## 設定

| 変数 | 効果 |
|---|---|
| `DEBUG_MODE=true` | ビルド時に `docs_dev/` を含める（`--public-only` でない場合）。Help ツールの読取では、既存の内部ポイントを含めることを既定にする |
| `HELP_DATA_DUMP` | 明示的なインストールと更新検出で使うダンプのパスを上書き |
| `HELP_CHUNK_SIZE` | チャンクあたりの文字数（既定 3000） |
| `HELP_OVERLAP_SIZE` | チャンク間のオーバーラップ（既定 500） |
| `HELP_CHUNKS_PER_RESULT` | 検索結果1件あたりのチャンク数（既定 3） |
| `KEEP_VECTOR_SERVICES=true` | ビルド後も embeddings コンテナを動かしたままにする |

`DEBUG_MODE` はビルドへの取り込みと Help ツールの既定の読取可視性を制御します。
ビルド側は `--public-only` が、読取側は明示的な `include_internal:` が上書きします。
インストール時の検証や検索可否の判定は回避しません。したがって
`help:build_internal` は、内部コンテンツの正式なインストール経路にはなりません。

`Monadic::Help.installation` が選ぶ既定のダンプは、コンテナ内では
`/monadic/help_data/help_db.json`、ホスト開発時は
`docker/services/ruby/help_data/help_db.json` です。どちらも `HELP_DATA_DUMP` で
上書きできます。インストール用インスタンスは必要時に生成し、利用可否や検索用
接続はキャッシュしません。

## ダンプの中身を確認する

```bash
ruby -rjson -e '
  d = JSON.parse(File.read("docker/services/ruby/help_data/help_db.json"))
  d["collections"].each do |name, c|
    n = c["points"].count { |p| p.dig("payload", "is_internal") }
    puts format("%-12s %5d points, %5d internal", name, c["points"].size, n)
  end'
```

## 関連

- [ヘルプシステム](../../../docs/ja/advanced-topics/help-system.md) — 公開ドキュメント
- `docker/services/ruby/scripts/utilities/process_documentation.rb`
- `docker/services/ruby/lib/monadic/utils/help_embeddings.rb`
- `rakelib/help.rake`
