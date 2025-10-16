# 外部JavaScriptライブラリ（ベンダーアセット）

Monadic Chatは、オフライン/パッケージ使用のために少数のサードパーティライブラリをベンダー化しています。提供されているスクリプトを使用してライブラリを追加または更新します。

場所：
- リスト：`docker/services/ruby/bin/assets_list.sh`
- インストーラー：`bin/assets.sh`
- 保存先：`docker/services/ruby/public/vendor/{css,js,fonts,webfonts}`

## ライブラリの追加方法

1) `docker/services/ruby/bin/assets_list.sh`を編集し、`ASSETS`に新しいエントリを追加：
- 形式：`"type,url,filename"`
- タイプ：`css`、`js`、`font`、`webfont`、`mathfont`

2) インストーラーを実行：
- `rake download_vendor_assets`
  - 内部的に`./bin/assets.sh`を実行し、`public/vendor`にファイルを配置

3) 検証：
- `docker/services/ruby/public/vendor`の下のファイルを確認
- Font Awesomeなどのcssの場合、`assets.sh`はwebfontのURLを`/vendor/webfonts/`に書き換える

ガイドライン：
- 固定バージョンの有名なCDN（cdnjs、jsdelivr）を優先
- キャッシュ可能性のためにファイル名を安定させる
- 明確な必要性がない限り大きなライブラリを避ける
