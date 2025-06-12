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

# ヘルプデータベースを構築（増分）
rake help:build

# ヘルプデータベースを最初から再構築
rake help:rebuild

# ヘルプデータベースをエクスポート
rake help:export

# ヘルプデータベースの統計情報を表示
rake help:stats
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

## ビルド

```bash
# アプリケーションパッケージをビルド
rake build
```

## テスト

```bash
# Rubyテストの実行
rake spec

# JavaScriptテストの実行（合格するテストのみ）
rake jstest

# 全てのJavaScriptテストの実行
rake jstest_all

# 全てのテストの実行（RubyとJavaScript）
rake test
```
