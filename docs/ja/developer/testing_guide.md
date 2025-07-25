# アプリのテスト

このガイドでは、カスタムMonadic Chatアプリケーションをテストする方法を説明します。

## クイックスタート

### アプリの手動テスト

1. **アプリをインストール** - `~/monadic/data/apps/`に配置
2. **Monadic Chatを再起動** - アプリを読み込むため
3. **コンソールパネルを開く** - アプリを選択
4. **各機能を体系的にテスト**：
   - 基本的な会話を試す
   - 定義したすべてのツールをテスト
   - エラー処理を確認
   - 異なるプロバイダーで検証

### テストスクリプトの作成

`~/monadic/data/scripts/`にテストスクリプトを作成してテストを自動化：

```ruby
# test_my_app.rb
require 'net/http'
require 'json'

# アプリの機能をテスト
puts "MyAppをテスト中..."

# 例：APIエンドポイントのテスト
uri = URI('http://localhost:4567/api/your_endpoint')
response = Net::HTTP.get(uri)
puts "レスポンス: #{response}"
```

## テストチェックリスト

### リリース前
- [ ] アプリがエラーなく読み込まれる
- [ ] すべてのツールが期待通りに動作
- [ ] システムプロンプトが明確で完全
- [ ] 複数のプロバイダーで動作
- [ ] エラーを適切に処理
- [ ] 説明とアイコンが適切

### テストすべき一般的な問題

1. **ツール実行**
   - ツールは期待通りに呼び出されるか？
   - パラメータは正しく渡されるか？
   - エラー処理は機能するか？

2. **プロバイダー互換性**
   - 少なくとも2-3の異なるプロバイダーでテスト
   - 機能が適切に劣化することを確認
   - モデル固有の動作を検証

3. **ファイル処理**
   - アプリが使用する場合はファイルアップロードをテスト
   - ファイルパスが正しいことを確認
   - ファイルサイズ制限を確認

4. **コンテキスト管理**
   - monadicアプリの場合、コンテキストの更新を確認
   - コンテキストサイズ制限を確認
   - コンテキストの永続性をテスト

## デバッグのヒント

### ログを有効化
1. コンソールパネルの設定に移動
2. 「Extra Logging」を有効化
3. 詳細な出力のためコンソールを監視

### Rubyコンソールを確認
コンソール出力でエラーを探す：
- MDSLファイルの構文エラー
- ツール定義の欠落
- ランタイム例外

### プリント文を使用
デバッグ出力をRubyコードに追加：
```ruby
def my_tool(param:)
  puts "DEBUG: my_toolがparam: #{param}で呼び出されました"
  # ツールのロジック
end
```

## パフォーマンステスト

### レスポンス時間
- ツールの実行時間を測定
- 不要なAPI呼び出しを確認
- 遅い操作を最適化

### メモリ使用量
- コンテナのメモリ使用量を監視
- 長い会話でのメモリリークを確認
- 大きなコンテキストサイズでテスト

## 統合テスト

アプリが外部サービスを使用する場合：

1. **開発中は外部APIをモック**
2. **リリース前に実際のAPIでテスト**
3. **APIの失敗を適切に処理**
4. **レート制限を尊重**

## テストシナリオの例

### チャットアプリのテスト
```
1. 挨拶で会話を開始
2. フォローアップの質問をする
3. コンテキストの保持をテスト
4. エッジケースを試す（空の入力、非常に長い入力）
5. 異なるモデルでテスト
```

### ツールベースアプリのテスト
```
1. 各ツールを個別にトリガー
2. ツールの組み合わせをテスト
3. 無効なパラメータを提供
4. エラー回復をテスト
5. 出力形式を確認
```

## ヘルプを得る

- テストパターンについて既存のアプリを確認
- ガイダンスのためMonadic Helpアプリを使用
- エラーのためコンソールログを確認
- 開発中は段階的にテスト

## ベストプラクティス

1. **早期かつ頻繁にテスト** - アプリが完成するまで待たない
2. **テストケースを文書化** - テストした内容をメモに残す
3. **バージョン管理を使用** - 変更前に動作するバージョンを保存
4. **ユーザーフィードバックを得る** - 他の人にアプリをテストしてもらう
5. **エッジケースをテスト** - 通常とは異なる入力やシナリオを試す