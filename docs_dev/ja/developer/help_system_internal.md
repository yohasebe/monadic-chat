# ヘルプデータベース内の内部ドキュメント

## 概要

Monadic Help のデータベースには、公開ドキュメント（`docs/`）と開発者向け内部
ドキュメント（`docs_dev/`）の両方を入れられます。各ポイントには `is_internal`
payload が付き、検索はこれでフィルタされます。

出荷されるデータベースに入るのは**公開ドキュメントだけ**です（`docs/` と、
ルートの `README.md`・`CHANGELOG.md`）。`rake help:build` は `--public-only` を
渡し、`HelpDumpGuard` が内部ポイントを含むダンプの梱包を拒否します。拒否は
`scripts/stage_docker_payload.rb` と、npm のビルドスクリプトが通る `beforePack`
フックの両方から効きます。`docs_dev/` も検索したい開発者は
`rake help:build_internal` で手元用のダンプを作ります。そのダンプは梱包しては
いけません（してもゲートが止めます）。

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

`HelpEmbeddings#find_closest_text` が Qdrant の payload フィルタを適用します。

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
`include_internal:` が優先されます。つまり `DEBUG_MODE=true` で動かしている
開発者は既定で両方のツリーを検索対象にでき、それ以外は公開ドキュメントのみを
検索します。

## Rake タスク

`rakelib/help.rake` で定義されています。

### help:build
`--public-only` を渡し、公開ドキュメントだけからダンプを再生成します。出荷
ビルドが走らせるのはこちらです。ポート 8002 に到達できなければ embeddings
コンテナを起動し、**このタスクが起動した場合にかぎり**終了後に停止します
（`KEEP_VECTOR_SERVICES=true` のときは停止しません）。

### help:build_internal
同じですが `--include-internal` を渡すので `docs_dev/` も対象になります。
手元の開発用のみ。生成されたダンプは梱包時に拒否されます。

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

`lib/monadic/utils/help_embeddings_loader.rb` は**コレクションが空のときだけ**
ダンプを読み込みます。

```ruby
unless db.data_loaded?
  Monadic::Help::DumpLoader.load(store: db.store, path: dump_path)
end
```

`Monadic::Help::DumpLoader` は upsert のみで削除を行いません。したがって新しい
ダンプを配っても既存インストールの内容は置き換わりません。「コレクションに
データがある」という短絡と upsert の両方を、古いポイントが生き延びます。
`HELP_DATA_DUMP` で別のパスを指しても同じ理由で読み込まれません。

したがってコレクションの削除は作業の半分にすぎません。コンテナはダンプを自身の
イメージ内から読むため、ホストでビルドしたばかりのダンプは、届けるまでコンテナに
見えません。内部ダンプを手元で検索するには次の順で行います。

1. `rake help:build_internal` でビルドする。
2. Ruby プロセスが読める場所へ届ける。Ruby イメージを再ビルドして
   `COPY help_data/` に新しいファイルを拾わせるか、ファイルをコンテナに
   マウントして `HELP_DATA_DUMP` をそのパスに向ける。
3. Qdrant の `help_docs` と `help_items` コレクションを削除し、ローダーが
   `data_loaded?` で短絡しないようにする。
4. Ruby コンテナを**作り直し**てから `DEBUG_MODE=true` で検索する。再起動では
   なく作り直しです。`docker restart` では古いイメージのままですし、新しい
   マウントや `HELP_DATA_DUMP` はそれを付けて起動したコンテナにしか効きません。

手順 2 を飛ばすと、イメージに既に入っている同じ公開ダンプを読み直すだけに
なります。Qdrant のボリューム全体を消さないでください。`library_*` と `pdf_*`
コレクションには利用者のデータが入っています。

## 設定

| 変数 | 効果 |
|---|---|
| `DEBUG_MODE=true` | ビルド時に `docs_dev/` を含め（`--public-only` でない場合）、**かつ**検索でも返す |
| `HELP_DATA_DUMP` | 起動時に読むダンプのパスを上書き |
| `HELP_CHUNK_SIZE` | チャンクあたりの文字数（既定 3000） |
| `HELP_OVERLAP_SIZE` | チャンク間のオーバーラップ（既定 500） |
| `HELP_CHUNKS_PER_RESULT` | 検索結果1件あたりのチャンク数（既定 3） |
| `KEEP_VECTOR_SERVICES=true` | ビルド後も embeddings コンテナを動かしたままにする |

`DEBUG_MODE` はビルドへの取り込みと検索での可視性を兼ねています。ビルド側は
`--public-only` が、検索側は明示的な `include_internal:` が上書きします。
いずれにしても公開ダンプには返せる内部文書自体がないので、内部文書を検索したい
開発者は、`help:build_internal` で作ったダンプをコンテナへ届け、そこから
コレクションを読み直す必要があります
（[既存インストールへの読み込み](#既存インストールへの読み込み)を参照）。

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
