# Monadic Chat開発ガイド

## 開発環境のセットアップ

### 前提条件

- Ruby 3.0+
- Docker Desktop
- ImageMagick（画像処理テスト用）

### 初期セットアップ

1. リポジトリをクローン
2. `docker/services/ruby`に移動
3. 依存関係をインストール：
   ```bash
   bundle install
   ```

### テストの実行

#### ユニットテスト（高速）
```bash
rake spec_unit
```

#### すべてのテスト
```bash
rake spec
```

#### 特定のテストファイルの実行
```bash
# office2txtテストを実行
bundle exec rspec spec/unit/scripts/office2txt_minimal_spec.rb

# PDF処理テストを実行
bundle exec rspec spec/unit/scripts/pdf2txt_docker_spec.rb
```

### テストの構成

- **ユニットテスト**（`spec/unit/`）：高速で独立したテスト
- **統合テスト**（`spec/integration/`）：外部依存関係を持つテスト
- **システムテスト**（`spec/system/`）：完全なアプリケーションテスト
- **E2Eテスト**（`spec/e2e/`）：エンドツーエンドワークフローテスト

### スクリプトのテスト作成

#### Rubyスクリプト
- Docker なしでローカルテスト
- 可能な限り外部依存関係をモック
- 一時ファイルを使用した実際のファイル操作を使用

#### Pythonスクリプト
- 常にDockerコンテナ経由でテスト
- テストファイルに共有ボリューム（`~/monadic/data`）を使用
- 各テスト後にテストアーティファクトをクリーンアップ

### よくある問題

1. **Dockerが動作していない**：Pythonスクリプトテストを実行する前にDocker Desktopを起動
2. **パーミッションエラー**：`~/monadic/data`ディレクトリが存在し、書き込み可能であることを確認
3. **ImageMagickが見つからない**：画像テスト用にImageMagickをインストール（macOSでは`brew install imagemagick`）

### コードスタイル

コードスタイルチェックにRuboCopを実行：
```bash
bundle exec rubocop
```
