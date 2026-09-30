# 開発者向けCDNアセット管理

## 概要

Web UI は、オフラインで動くように、サードパーティライブラリを `/vendor` から配信します。これらはダウンロードされるもので git では追跡しないため、`assets_list.sh` がその中身を示す唯一の記録です。各エントリは、バージョンを含む URL とファイルの sha256 を固定します。

## ファイル

- `/docker/services/ruby/bin/assets_list.sh`: 一覧と、それを読むすべての側が使うシェル関数（`vendor_manifest`、`vendor_fetch`）
- `/bin/assets.sh`: ソースツリーへ取得する（`rake download_vendor_assets`。`rake build` でも実行される）
- `/docker/services/ruby/scripts/download_assets.sh`: Ruby イメージのビルド中に実行される
- `/scripts/build_products.rb`: 同じ一覧をパッケージングのゲートから読む

## 新しいアセットの追加方法

1. バージョンを含む URL からファイルを取得し、sha256 を求める
2. `ASSETS` 配列にエントリを追加する：
   ```
   "type,url,filename,sha256"
   ```
   - `type`: `css`（vendor/css）、`js`（vendor/js）、`font`（vendor/fonts）、`webfont`（vendor/webfonts）
   - `url`: バージョンを含み、同じバイト列を返し続ける URL
   - `sha256`: ダウンロードしたままのファイルの値。取得後にファイルを書き換えることはない
3. `rake download_vendor_assets` を実行する

## 取得の仕組み

`vendor_fetch` は、hash が固定値と一致するファイルは残し、それ以外は取得し直します（`curl --fail`）。取得の失敗や hash の不一致はエラーで停止するため、HTTP のエラーページがアセットとして保存されることはありません。あわせて `MONTSERRAT_CSS` から `css/montserrat.css` を書き出し、`css/fonts` を `../fonts` へのリンクにします。`katex.min.css` はこの場所で KaTeX のフォントを探します。

maxGraph にはダウンロードできるブラウザ向けビルドがありません。`npm run build:maxgraph` が、ロックされた `@maxgraph/core` から `vendor/js/maxgraph.bundle.js` を作ります。

## Docker統合

Ruby イメージはアプリのペイロードから `public/` をコピーします。ペイロードには vendor ファイルが既に入っており、その後で `download_assets.sh` を実行します。hash が一致するので、イメージのビルドでこれらのためにネットワークは必要ありません。本番で配信されるのはペイロードにあるファイルです。

## パッケージングのゲート

- `stage_docker_payload.rb` は、`vendor_manifest` が挙げるファイルに、フォントへのリンクと maxGraph のバンドルを加えたものだけを出荷します。vendor ディレクトリにあるそれ以外のファイルは出荷しません。一覧にあるファイルの hash が固定値と違えば、staging は停止します
- `verify_bundle_payload.rb` は、各アーカイブ内の vendor ファイルをすべて固定値と比べます。さらに、staging が読んだコミットのクリーンな worktree で JS バンドルと maxGraph のバンドルを作り直し、梱包されたものと比べます
