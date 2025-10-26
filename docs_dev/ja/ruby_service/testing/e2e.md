# エンドツーエンド（E2E）テスト

このディレクトリには、実際のAIプロバイダーAPIを呼び出さずにUI/サーバー配線とローカルワークフローを検証するエンドツーエンドテストが含まれています。実際のAPIカバレッジは spec/integration の spec_api に移動されました。

## 概要

E2Eテストはローカルサーバーとのユーザーインタラクションをシミュレートし、次に焦点を当てます：
- WebSocket通信とメッセージフロー
- ローカルツール実行とファイル操作
- 基本的なアプリ配線とリグレッション
実際のプロバイダーAPIの動作は spec/integration で検証されます（spec_api下のRakeタスクを参照）。

## テスト構造

```
e2e/
├── jupyter_notebook_grok_spec.rb      # Jupyterローカル操作（実際のAPIなし）
├── monadic_context_display_spec.rb    # モックレスポンスを使用したMonadic JSON表示
├── shared_examples/                   # 再利用可能なテスト例
├── e2e_helper.rb                      # WebSocket接続ヘルパー
├── validation_helper.rb               # 柔軟な検証メソッド
└── run_e2e_tests.sh                   # テストランナースクリプト
```

## テストの実行

### すべてのE2Eテスト（実際のAPIなし）
```bash
rake spec_e2e  # 実際のプロバイダーAPIにヒットしない
```

### 特定のアプリテスト
```bash
rake spec_e2e:chat              # Chatアプリのみ
rake spec_e2e:code_interpreter   # すべてのCode Interpreterテスト
rake spec_e2e:image_generator    # Image Generatorのみ
rake spec_e2e:pdf_navigator      # PDF Navigatorのみ
rake spec_e2e:help              # Monadic Helpのみ
```

実際のAPIプロバイダーテストは spec_api タスクにあります。例：
```bash
# プロバイダー間の非メディアAPI smoke（デフォルトでOllama除外）
RUN_API=true PROVIDERS=openai,anthropic bundle exec rake spec_api:smoke

# メディア（画像/音声）APIテスト
RUN_API=true RUN_MEDIA=true bundle exec rake spec_api:media
```

### 手動テスト実行
```bash
cd docker/services/ruby
bundle exec rspec spec/e2e/jupyter_notebook_grok_spec.rb
bundle exec rspec spec/e2e/monadic_context_display_spec.rb:23  # 特定の行
```

## テスト哲学

1. **実際のAPIなし**：E2Eは実際のプロバイダーエンドポイントを呼び出さない
2. **機能的配線**：メッセージフローとUI/サーバー接着を検証
3. **最小限の冗長性**：実際のAPIシナリオは spec_api に属する
4. **柔軟なアサーション**：堅牢で動作指向のチェックを優先
5. **クリーンリトライ**：必要に応じてカスタムリトライヘルパーが利用可能

## 主要なテストパターン

### コード実行検証
```ruby
expect(code_execution_attempted?(response)).to be true
```

### 柔軟なコンテンツマッチング
```ruby
expect(response.downcase).to match(/keyword1|keyword2|keyword3/i)
```

### システムエラーハンドリング
```ruby
skip "System error or tool failure" if system_error?(response)
```

## 前提条件

- 必要に応じてローカルサービス用のDockerコンテナ（自動起動）
- `localhost:4567`上のサーバー（必要に応じて自動起動）
- E2EにはプロバイダーのAPIキーは不要

## 新しいE2Eテストの作成

### 基本構造
```ruby
require_relative 'e2e_helper'

RSpec.describe "Feature E2E Workflow", type: :e2e do
  include E2EHelper

  before(:all) do
    unless check_containers_running
      skip "E2E tests require all containers to be running"
    end

    unless wait_for_server
      skip "E2E tests require server to be running"
    end
  end

  it "completes user workflow" do
    ws_connection = create_websocket_connection

    send_chat_message(ws_connection, "Your message", app: "AppName")
    response = wait_for_response(ws_connection)

    expect(response).to include("expected content")

    ws_connection[:client].close
  end
end
```

### ベストプラクティス

1. **常に前提条件をチェック** `before(:all)`ブロックで
2. **リソースをクリーンアップ** `after`ブロックで
3. **わかりやすいテスト名を使用** ワークフローを説明する
4. **成功パスと失敗パスの両方をテスト**
5. **関連する場合はパフォーマンス期待を含める**
6. **信頼性のために外部サービスをモック** 必要な場合

## デバッグ

### 詳細出力を有効化：
```bash
VERBOSE=true bundle exec rspec spec/e2e
```

### よくある問題

1. **「サーバーが実行されていません」エラー**
   - サーバーが起動されていることを確認：`rake server`
   - ポート4567が使用されていないことを確認

2. **「コンテナが実行されていません」エラー**
   - コンテナを起動：`./docker/monadic.sh start`
   - 確認：`docker ps | grep monadic`

3. **タイムアウトエラー**
   - `wait_for_response`のタイムアウトを増やす
   - APIキーが有効であることを確認
   - ネットワーク接続を確認

4. **WebSocket接続失敗**
   - ファイアウォール設定をチェック
   - WebSocketポート（4567）がアクセス可能であることを確認
   - サーバーログでエラーを探す

## CI/CD統合

これらのテストはCI環境で実行するように設計されています：

```yaml
# GitHub Actions設定の例
- name: Start services
  run: |
    ./docker/monadic.sh build
    ./docker/monadic.sh start
    rake server &
    sleep 10

- name: Run E2E tests
  run: |
    cd docker/services/ruby
    bundle exec rspec spec/e2e --format documentation
```

## パフォーマンスベンチマーク

通常の条件下での期待されるレスポンス時間：
- 単純なチャットクエリ：< 5秒
- コード実行：< 10秒
- PDF検索：< 15秒
- マルチステップワークフロー：< 30秒

## 将来の改善

計画された改善：
- [ ] 並列テスト実行
- [ ] 生成されたチャートの視覚的リグレッションテスト
- [ ] 複数の同時ユーザーでの負荷テスト
- [ ] Web UIのクロスブラウザテスト
- [ ] モバイルアプリ統合テスト
