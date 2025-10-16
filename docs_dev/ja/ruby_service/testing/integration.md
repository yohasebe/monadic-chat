# Docker 統合テスト

このディレクトリには、Monadic ChatとDockerコンテナ間のインタラクションを検証する統合テストが含まれています。

## 前提条件

1. Dockerがインストールされ、実行されている必要があります
2. Monadic Chatコンテナがビルドされ、実行されている必要があります：
   ```bash
   ./docker/monadic.sh build
   ./docker/monadic.sh start
   ```

## テストの実行

### すべての統合テストを実行：
```bash
rake spec_integration
```

### Docker固有のテストのみ実行：
```bash
rake spec_docker
```

### 特定のテストファイルを実行：
```bash
cd docker/services/ruby
bundle exec rspec spec/integration/docker_integration_spec.rb
```

## テストカバレッジ

### docker_integration_spec.rb
- 基本的なコンテナ通信
- Pythonコード実行
- コンテナ間のファイル共有
- エラーハンドリング

### app_docker_integration_spec.rb
- Code Interpreter機能
- データサイエンスライブラリ（pandas、matplotlib、numpy）
- ファイル処理ツール
- マルチコンテナワークフロー

### container_helpers_integration_spec.rb
- PythonContainerHelperメソッド
- BashCommandHelperメソッド
- ReadWriteHelperメソッド
- クロスヘルパー統合

### pgvector_integration_spec.rb
- PostgreSQL/pgvector接続（プレースホルダー）
- ベクトル操作（プレースホルダー）
- 埋め込みストレージ（プレースホルダー）

## 新しいDocker統合テストの作成

新しいDocker統合テストを作成する際：

1. 常にDockerが利用可能かチェック：
   ```ruby
   before(:all) do
     skip "Docker tests require Docker environment" unless docker_available?
   end
   ```

2. コンテナインタラクション用のヘルパーメソッドを使用：
   ```ruby
   result = execute_in_container(
     code: "print('Hello')",
     command: "python",
     container: "python"
   )
   ```

3. 生成されたファイルをクリーンアップ：
   ```ruby
   # クリーンアップ
   File.delete(test_file) if File.exist?(test_file)
   ```

4. 成功ケースと失敗ケースの両方をテスト

## トラブルシューティング

### テストがスキップされる
- Dockerが実行中であることを確認：`docker ps`
- コンテナが実行中であることを確認：`./docker/monadic.sh status`

### パーミッションエラー
- ~/monadic/dataのファイルパーミッションをチェック
- 現在のユーザーがDockerパーミッションを持っていることを確認

### コンテナが見つからない
- コンテナ名がパターンに一致することを確認：`monadic-chat-{service}-container`
- コンテナが実行中であることをチェック：`docker ps | grep monadic`
