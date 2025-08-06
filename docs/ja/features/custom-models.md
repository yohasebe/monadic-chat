# カスタムモデル設定

Monadic Chatでは、カスタム`models.json`ファイルを作成することで、モデルの仕様をカスタマイズできます。この機能により以下が可能になります：

- デフォルト設定に含まれていない新しいモデルの追加
- 既存モデルのパラメータのオーバーライド
- temperature、max tokensなどのデフォルト値のカスタマイズ

## セットアップ

1. Monadic Chatの設定ディレクトリに`models.json`という名前のファイルを作成します：
   ```
   ~/monadic/config/models.json
   ```

2. JSON形式でカスタムモデル定義またはオーバーライド設定を追加します。

## ファイル形式

`models.json`ファイルは以下の形式のJSONオブジェクトを含む必要があります：
- キー：モデル名（例："gpt-4"、"claude-3-opus"）
- 値：モデル仕様オブジェクト

## 例

### 新しいモデルの追加

```json
{
  "gpt-5-preview": {
    "context_window": [1, 2000000],
    "max_output_tokens": [1, 200000],
    "temperature": [[0.0, 2.0], 1.0],
    "top_p": [[0.0, 1.0], 1.0],
    "presence_penalty": [[-2.0, 2.0], 0.0],
    "frequency_penalty": [[-2.0, 2.0], 0.0],
    "tool_capability": true,
    "vision_capability": true,
    "reasoning_effort": [["low", "medium", "high"], "medium"]
  }
}
```

### 既存モデルのパラメータのオーバーライド

モデル全体を再定義することなく、特定のパラメータのみをオーバーライドできます：

```json
{
  "gpt-4": {
    "temperature": [[0.0, 2.0], 0.7],
    "max_output_tokens": [1, 8192]
  },
  "claude-3-opus-20240229": {
    "temperature": [[0.0, 1.0], 0.5]
  }
}
```

## パラメータリファレンス

### 共通パラメータ

- **context_window**: `[最小値, 最大値]` - 入力コンテキストのトークン制限
- **max_output_tokens**: `[最小値, 最大値]` または `[[最小値, 最大値], デフォルト値]` - レスポンスの最大トークン数
- **temperature**: `[[最小値, 最大値], デフォルト値]` - 創造性/ランダム性の制御
- **top_p**: `[[最小値, 最大値], デフォルト値]` - Nucleus samplingパラメータ
- **presence_penalty**: `[[最小値, 最大値], デフォルト値]` - トピック繰り返しへのペナルティ
- **frequency_penalty**: `[[最小値, 最大値], デフォルト値]` - 単語の繰り返しへのペナルティ

### 機能フラグ

- **tool_capability**: `boolean` - モデルが関数呼び出しをサポートするか
- **vision_capability**: `boolean` - モデルが画像を処理できるか
- **reasoning_effort**: `[オプション配列, デフォルト値]` - 思考/推論モードを持つモデル用

## 動作の仕組み

1. Monadic Chat起動時、デフォルトの`model_spec.js`を読み込みます
2. `~/monadic/config/models.json`が存在する場合、カスタム仕様をマージします
3. カスタム仕様はディープマージを使用してデフォルト値を上書きします
4. マージされた設定がアプリケーション全体で使用されます

## トラブルシューティング

### 無効なJSONエラー

無効なJSONに関するエラーが表示される場合：
1. JSONバリデータを使用してJSON構文を検証してください
2. 末尾のカンマがないか確認してください（JSONでは許可されていません）
3. すべての文字列がダブルクォートで囲まれているか確認してください

### モデルが表示されない

カスタムモデルが表示されない場合：
1. ブラウザコンソールでエラーメッセージを確認してください
2. ファイルが正しい場所にあることを確認：`~/monadic/config/models.json`
3. 変更後、Monadic Chatサーバーを再起動してください

### 開発環境と本番環境

- **開発環境** (`rake server:debug`)：`~/monadic/config/models.json`から読み込み
- **本番環境** (Docker)：`/monadic/config/models.json`から読み込み（自動マッピング）

## サンプルファイル

完全なサンプルファイルは以下で利用可能です：
```
docs/examples/models.json.example
```

このファイルを`~/monadic/config/models.json`にコピーして、必要に応じて修正してください。