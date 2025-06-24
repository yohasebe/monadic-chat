# 開発者向けMonadic Chat Rakeタスク

Monadic Chatは開発、テスト、ビルド、リリース管理を簡素化するための包括的なRakeタスクセットを提供しています。

## デフォルトタスク

```bash
# specとrubocopの両方を実行（デフォルトタスク）
rake
```

## サーバー管理

```bash
# デーモンモードでサーバーを起動
rake start
rake server:start

# デバッグモード（フォアグラウンド、EXTRA_LOGGING=true）でサーバーを起動
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

### ドキュメントデータベース

```bash
# ドキュメントデータベースをエクスポート
rake db:export

# ドキュメントデータベースをインポート
rake db:import
```

### ヘルプデータベース

```bash
# ヘルプデータベースを構築（増分）
rake help:build

# ヘルプデータベースを最初から再構築
rake help:rebuild

# 配布用にヘルプデータベースをエクスポート
rake help:export

# ヘルプデータベースの統計情報を表示
rake help:stats
```

**注意**: ヘルプデータベースタスクはpgvectorコンテナが実行中である必要があります。

## アセット管理

```bash
# CDNからベンダーアセットをダウンロード
rake download_vendor_assets
```

## バージョン管理

```bash
# 全ファイルのバージョン一貫性をチェック
rake check_version

# バージョン番号の更新（CHANGELOG.mdも自動更新）
rake update_version[to_version]
rake update_version[from_version,to_version]

# ドライランモード
DRYRUN=true rake update_version[to_version]
```

## ビルドタスク

```bash
# 全プラットフォームのパッケージをビルド
rake build

# プラットフォーム別ビルド
rake build:win           # Windows x64
rake build:mac           # 両方のmacOSパッケージ
rake build:mac_arm64     # macOS arm64 (Apple Silicon)
rake build:mac_x64       # macOS x64 (Intel)
rake build:linux         # 両方のLinuxパッケージ
rake build:linux_x64     # Linux x64
rake build:linux_arm64   # Linux arm64
```

## リリース管理

**注意**: GitHub CLI (`gh`) がインストールされ、認証されている必要があります。

```bash
# 新しいGitHubリリースを作成
rake release:github[version,prerelease]

# ドラフトリリースを作成
rake release:draft[version,prerelease]
DRAFT=true rake release:github[version,prerelease]

# 全てのリリースを一覧表示
rake release:list

# リリースとそのタグを削除
rake release:delete[version]

# 既存リリースのアセットを更新
rake release:update_assets[version,file_patterns]
UPDATE_CHANGELOG=true rake release:update_assets[version,file_patterns]
```

## 注意事項

### 環境変数

- `EXTRA_LOGGING=true` - 詳細ログを有効化（デバッグモードで自動設定）
- `DRYRUN=true` - バージョン更新をドライランモードで実行
- `DRAFT=true` - GitHubリリースをドラフトとして作成
- `UPDATE_CHANGELOG=true` - リリースアセット更新時にchangelogを更新

### 開発環境

Docker外で実行する場合、Rakefileは自動的に以下を設定します：
- `POSTGRES_HOST=localhost`
- `POSTGRES_PORT=5433` （ローカルPostgreSQLとの競合を回避）

### バージョン更新

`update_version`タスクは以下のファイルのバージョン番号を更新します：
- `lib/monadic/version.rb`
- `package.json`と`package-lock.json`
- `monadic.sh`
- ドキュメントファイル
- `CHANGELOG.md`（新しいバージョンセクションを追加）

## テストとコード品質

```bash
# すべてのRubyテストの実行（RSpec）
rake spec

# 特定のテストカテゴリの実行
rake spec_unit        # ユニットテストのみ（高速）
rake spec_integration # 統合テスト
rake spec_system      # システムテスト（MDSL検証）
rake spec_e2e         # エンドツーエンドテスト（サーバー起動が必要）

# Rubyコードスタイルチェック
rake rubocop

# JavaScriptのLintチェック
rake eslint

# JavaScriptテストの実行（Jest）
rake jstest
rake jstest_all  # 後方互換性のためのエイリアス

# 全てのテストの実行（RubyとJavaScript）
rake test
```

### E2Eテスト

`rake spec_e2e`タスクは包括的なエンドツーエンドテストを提供します：
- Dockerコンテナが動作していることを確認
- サーバーが起動していない場合は自動的に起動
- 設定されたすべてのプロバイダーでWebSocketベースのテストを実行
- プロバイダーカバレッジサマリーを表示
- 一時的な障害に対するリトライメカニズムを含む
