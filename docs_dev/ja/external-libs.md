# 外部JavaScriptライブラリ（ベンダーアセット）

Monadic Chatは、オフライン/パッケージ使用のために少数のサードパーティライブラリをベンダー化しています。各ファイルはバージョンと sha256 で固定されています。一覧の読み方と検査は [CDNアセット管理](developer/assets.md) を参照してください。

場所：
- リスト：`docker/services/ruby/bin/assets_list.sh`
- インストーラー：`bin/assets.sh`
- 保存先：`docker/services/ruby/public/vendor/{css,js,fonts,webfonts}`

## ライブラリの追加方法

1) バージョンを含む URL からファイルを取得し、hash を求める：
- `curl --fail -L -o lib.js "<url>" && shasum -a 256 lib.js`

2) `docker/services/ruby/bin/assets_list.sh`の`ASSETS`にエントリを追加：
- 形式：`"type,url,filename,sha256"`
- タイプ：`css`、`js`、`font`、`webfont`

3) インストーラーを実行：
- `rake download_vendor_assets`
  - `./bin/assets.sh`を実行する。無いファイルと固定値に一致しないファイルを取得し、取得の失敗や hash の不一致で停止する

ガイドライン：
- バージョンを含む URL を使う（cdnjs、jsdelivr の `@x.y.z`、git のタグ）。最新版を返す URL は、上流の更新で固定値と一致しなくなる
- ライブラリを更新するときは URL と hash を同時に変える
- 明確な必要性がない限り大きなライブラリを避ける
