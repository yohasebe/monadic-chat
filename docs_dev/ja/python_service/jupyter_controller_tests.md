# Jupyter Controller テスト

このディレクトリには、Monadic ChatのJupyterノートブックを管理する`jupyter_controller.py`スクリプトのテストが含まれています。

## テストファイル

1. **test_jupyter_controller.py** - Pythonユニットテスト
   - すべての関数を分離してテスト
   - ファイルシステム依存関係を避けるためにモックを使用
   - エラーハンドリングとエッジケースを検証

2. **jupyter_controller_integration_spec.rb** - Ruby統合テスト
   - 場所：`docker/services/ruby/spec/integration/`
   - Rubyコードから呼び出されるスクリプトをテスト
   - コマンドラインインターフェースを検証
   - 実際のファイル操作をテスト

## テストの実行

### Pythonユニットテスト

```bash
# すべてのテストを実行
python3 test_jupyter_controller.py

# 詳細出力で実行
python3 test_jupyter_controller.py -v

# 特定のテストクラスを実行
python3 test_jupyter_controller.py TestJupyterController

# pytestで実行（インストールされている場合）
python3 -m pytest test_jupyter_controller.py -v
```

### Ruby統合テスト

Rubyサービスディレクトリから：
```bash
cd docker/services/ruby
bundle exec rspec spec/integration/jupyter_controller_integration_spec.rb
```

## テストカバレッジ

このテストは以下をカバーします：

### コア機能
- タイムスタンプ付きの新しいノートブックの作成
- セルの追加（markdownとcode）
- ノートブックコンテンツの読み取り
- 既存セルの更新
- セルの削除
- セル内のコンテンツの検索

### セルフォーマットハンドリング
- 'content'フィールドを持つ標準フォーマット
- 'source'フィールド（文字列）を持つ代替フォーマット
- 'source'フィールド（配列）を持つ代替フォーマット
- 'type'と'cell_type'フィールド名の混在

### エラーハンドリング
- 存在しないノートブック
- 無効なJSON入力
- 無効なセルタイプ
- 範囲外のセルインデックス
- 再試行メカニズムを持つファイルI/Oエラー

### コマンドラインインターフェース
- すべてのサブコマンド（create、read、add、display、delete、update、search）
- バッチ操作用のJSONファイル入力
- 適切なエラーメッセージと終了コード

## 実装ノート

1. コントローラーは一時的なロックを処理するためにファイル操作に再試行メカニズムを使用
2. セルコンテンツは互換性のために複数のフォーマットで提供可能
3. すべてのパスは本番環境で`/monadic/data/`に相対
4. タイムスタンプは一意性を保証するために作成されたノートブックに追加

## 将来の改善

- セルメタデータのサポートを追加
- ノートブックマージ機能を実装
- 異なるフォーマットへのノートブックエクスポートのサポートを追加
- セル実行追跡を実装
