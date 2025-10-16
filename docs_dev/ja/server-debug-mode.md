# サーバーデバッグモード

## 概要

`rake server:debug`は、ローカルのRuby環境を使用して、Monadicサーバーを非デーモン化デバッグモードで起動します。その他のコンテナ（Python、pgvector、Seleniumなど）は必要に応じて起動・再利用されます。

このモードで有効になる機能：
- **追加ログ** - プロバイダーのリクエスト/レスポンスをデバッグするための詳細ログ
- **ローカルドキュメントアクセス** - 内部・外部両方のドキュメントへのアクセス
- **直接Ruby実行** - コンテナのオーバーヘッドなしで実行

## クイックスタート

```bash
# デバッグモードでサーバーを起動
rake server:debug

# アプリケーションにアクセス
open http://localhost:4567/

# ドキュメントにアクセス（デバッグモードのみ）
open http://localhost:4567/docs/          # 外部ドキュメント
open http://localhost:4567/docs_dev/      # 内部ドキュメント
```

## 機能

### 自動設定

`rake server:debug`を実行すると、以下が自動的に設定されます：

1. **`EXTRA_LOGGING=true`** - 詳細なプロバイダー/デバッグログを有効化
2. **`DEBUG_MODE=true`** - ローカルドキュメント配信を有効化
3. **Ollama検出** - Ollamaコンテナの利用可能性をチェック
4. **設定読み込み** - APIキーのために`~/monadic/config/env`を読み込み

実行例：
```
Starting Monadic server in debug mode...
Extra logging: enabled (forced in debug mode)
Debug mode: enabled (local documentation available)
```

### ローカルドキュメントアクセス

デバッグモードでは、内部・外部両方のドキュメントがローカルで配信されます：

**Web UI統合：**
- デバッグモードでは、Web UIに**ローカルドキュメントリンク**が表示されます
- 通常モードでは、Web UIに**GitHub Pagesリンク**が表示されます

**利用可能なドキュメント：**
- **外部ドキュメント**（`/docs/`） - ユーザー向けドキュメント
- **内部ドキュメント**（`/docs_dev/`） - 開発者向けドキュメント

### メリット

- **コンテナのオーバーヘッドなし** - Rubyがマシン上で直接実行される
- **高速な反復** - Rubyコードの変更が即座に反映される
- **豊富なログ** - プロバイダーのリクエスト/レスポンス全体を確認できる
- **ローカルドキュメント** - GitHubにプッシュせずにドキュメントの変更をプレビュー

## 使用タイミング

### `rake server:debug`を使用する場合：
- Rubyサービス（`docker/services/ruby`）のコードを反復開発する場合
- 追加ログでプロバイダーのリクエスト/レスポンスを調査する場合
- ドキュメントを編集してローカルで変更をプレビューしたい場合
- 詳細ログでアプリケーションの動作をデバッグする場合

### `rake server:start`を使用する場合：
- 本番環境に近い環境で実行する場合
- 完全なDockerコンテナセットアップをテストする場合
- 詳細なログが不要な場合
- バックグラウンドデーモンとして実行する場合

## 技術詳細

### ルート設定

ドキュメントルートは`DEBUG_MODE=true`の場合のみ有効になります：

```ruby
# monadic.rb
get "/docs_dev/?*" do
  unless CONFIG["DEBUG_MODE"]
    status 404
    return "Documentation not available in production mode"
  end
  # ... docs_dev/からファイルを配信
end
```

**重要：** `/docs_dev/?*`ルートは、パスマッチングの競合を防ぐために`/docs/?*`より**前に**配置する必要があります。

### パス解決

パスは実行時に`lib/monadic.rb`からの相対パスで解決されます：

```ruby
# docker/services/ruby/lib/monadic.rbからdocs_dev/への相対パス
docs_dev_root = File.expand_path("../../../../../docs_dev", __FILE__)

# docker/services/ruby/lib/monadic.rbからdocs/への相対パス
docs_root = File.expand_path("../../../../../docs", __FILE__)
```

このアプローチにより、プラットフォームに依存しない実装が保証されます - ハードコードされたパスはありません。

### セキュリティ機能

1. **パストラバーサル保護** - リクエストパスから`..`を削除
2. **ディレクトリ境界の強制** - ファイルが許可されたディレクトリ内にあることを検証
3. **本番環境保護** - DEBUG_MODEが無効の場合は404を返す

## 設定

### Rakefile

```ruby
desc "Start the Monadic server in debug mode (non-daemonized)"
task :debug do
  # デバッグモードでEXTRA_LOGGINGを強制的にtrueに設定
  ENV['EXTRA_LOGGING'] = 'true'

  # ローカルドキュメント用にDEBUG_MODEを有効化
  ENV['DEBUG_MODE'] = 'true'

  # 設定を読み込み
  config_path = File.expand_path("~/monadic/config/env")
  Dotenv.load(config_path) if File.exist?(config_path)

  # サーバーを起動
  sh "./bin/monadic_server.sh debug"
end
```

### monadic.rb

```ruby
# デフォルト値でCONFIGを初期化
CONFIG = {
  "EXTRA_LOGGING" => ENV["EXTRA_LOGGING"] == "true" || false,
  "DEBUG_MODE" => ENV["DEBUG_MODE"] == "true" || false,
  # ...
}

# 環境変数で上書き
if ENV["DEBUG_MODE"]
  CONFIG["DEBUG_MODE"] = ENV["DEBUG_MODE"] == "true"
end
```

### index.erb

条件付きUI表示：

```erb
<% if @debug_mode %>
  <!-- ローカルドキュメントリンクを表示 -->
  <a href="/docs/">Docs</a> <small style="color: #28a745;">(local)</small>
  <a href="/docs_dev/">Docs Dev</a> <small style="color: #dc3545;">(internal)</small>
<% else %>
  <!-- GitHub Pagesリンクを表示 -->
  <a href="https://yohasebe.github.io/monadic-chat/">Homepage</a>
<% end %>
```

## トラブルシューティング

### ドキュメントが404を返す

**症状：** ドキュメントリンクをクリックすると「File not found」が表示される

**解決方法：**
1. デバッグモードが有効であることを確認：
   ```bash
   rake server:debug
   # 「Debug mode: enabled (local documentation available)」と表示されるはず
   ```

2. ファイルが存在することを確認：
   ```bash
   ls docs_dev/index.html
   ls docs/index.html
   ```

3. `EXTRA_LOGGING`でログを確認：
   ```
   [DEBUG_MODE] Docs_dev request: requested_path='', docs_dev_root='/path/to/docs_dev'
   [DEBUG_MODE] Trying to serve: /path/to/docs_dev/index.html
   ```

### サーバーが起動しない

**一般的な原因：**
- ポート4567が既に使用中
- 依存関係が不足（`bundle install`）
- Dockerコンテナが実行されていない

**解決方法：**
```bash
# ポートを確認
lsof -i :4567

# 依存関係をインストール
bundle install

# Dockerが実行中であることを確認
docker ps
```

## 関連タスク

- `rake server:start` - `./bin/monadic_server.sh start`経由のデーモン化モード
- `rake server:stop` - ローカルで実行中のサーバーを停止
- `rake server:restart` - サーバーを再起動
- `rake spec` - テストを実行

## プラットフォームサポート

すべてのUnix系システムで動作：
- ✅ macOS（Darwin）
- ✅ Linux（Ubuntu、Debian、CentOSなど）
- ✅ BSD（FreeBSDなど）

## 関連項目

- [ロギング](logging.md) - デバッグログ設定
- [よくある問題](common-issues.md) - 一般的なトラブルシューティング
- [Dockerアーキテクチャ](docker-architecture.md) - サーバーアーキテクチャ概要
- [README](README.md) - ドキュメント構成
