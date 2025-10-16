# Environment Module サマリー

## 概要
コンテナ検出とパス解決は`Monadic::Utils::Environment`モジュールによって処理されます。

## 主要機能
- **コンテナ検出**：`in_container?`メソッド
- **パス解決**：コンテナとローカル実行の自動パス調整
- **PostgreSQL設定**：正しいホスト/ポートを持つ`postgres_params`メソッド

## 使用方法
```ruby
# 環境をチェック
if Monadic::Utils::Environment.in_container?
  # コンテナ固有のロジック
end

# データベース接続を取得
conn = PG.connect(Monadic::Utils::Environment.postgres_params)

# パスを取得
data_path = Monadic::Utils::Environment.data_path
scripts_path = Monadic::Utils::Environment.scripts_path
plugins_path = Monadic::Utils::Environment.plugins_path
```

## 利用可能なメソッド
- `in_container?` - Dockerコンテナ内で実行している場合にtrueを返す
- `data_path` - 正しいデータディレクトリパスを返す
- `scripts_path` - 正しいスクリプトディレクトリパスを返す
- `plugins_path` - 正しいプラグインディレクトリパスを返す
- `postgres_params(database: nil)` - PostgreSQL接続パラメータを返す
