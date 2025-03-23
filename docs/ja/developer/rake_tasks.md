# 開発者向けMonadic Chat Rakeタスク

Monadic Chatは開発と管理を簡素化するためのRakeタスクセットを提供しています。これらは`monadic_server.sh`コマンドのラッパーです。

## サーバー管理

```bash
# デーモンモードでサーバーを起動
rake start
rake server:start

# デバッグモード（フォアグラウンド）でサーバーを起動
rake debug
rake server:debug

# サーバーを停止
rake stop
rake server:stop

# サーバーを再起動
rake server:restart

# サーバーとコンテナのステータスを表示
rake status
rake server:status
```

## データベース操作

```bash
# ドキュメントデータベースをエクスポート
rake db:export

# ドキュメントデータベースをインポート
rake db:import
```

## アセット管理

```bash
# CDNからベンダーアセットをダウンロード
rake download_vendor_assets
```

## バージョン管理

```bash
# バージョン一貫性のチェック
rake check_version

# バージョン番号の更新
rake update_version[from_version,to_version]
```

## テスト＆リンティング

```bash
# スペックを実行
rake spec

# RuboCopを実行
rake rubocop
rake rubocop:autocorrect
rake rubocop:autocorrect_all
```

## ビルド

```bash
# アプリケーションパッケージをビルド
rake build
```