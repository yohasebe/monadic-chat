# DeepSeek アーキテクチャ

このドキュメントでは、Monadic ChatのDeepSeek統合におけるアーキテクチャと設計決定について説明します。

## 概要

DeepSeek統合（`docker/services/ruby/lib/monadic/adapters/vendors/deepseek_helper.rb`）は、DeepSeekモデル用のRubyアダプターを提供します。以下を処理します：
- APIリクエストのフォーマット
- レスポンスのストリーミング
- ツール/関数呼び出し（DSMLパースを含む）
- 推論コンテンツの抽出
- 関数呼び出しのStrictモード
- 不正なレスポンスに対する自動リトライメカニズム
- エラー処理

## 利用可能なモデル

| モデル | タイプ | ツール呼び出し | 推論 |
|-------|------|--------------|-----------|
| `deepseek-chat` | チャット（V3.2） | 対応 | なし |
| `deepseek-reasoner` | 推論（V3.2） | 対応 | あり |

## deepseek_helper.rbにおける設計決定

### 1. DSML（DeepSeek Markup Language）パース

**問題**: DeepSeekモデルは、標準のOpenAI互換`tool_calls` JSON形式の代わりに、独自のDSML形式でツール呼び出しを出力することがあります。

**DSML形式の例**:
```
<｜DSML｜function_calls>
<｜DSML｜invoke name="write_file">
<｜DSML｜param name="filename">test.txt</｜DSML｜/param>
<｜DSML｜param name="content">Hello World</｜DSML｜/param>
</｜DSML｜/invoke>
</｜DSML｜/function_calls>
```

**解決策**: ヘルパーには包括的なDSMLパーサーが含まれています：

1. **バリエーションの正規化**:
   - 全角パイプ（`｜`）→ ASCIIパイプ（`|`）
   - 異なる終了タグ形式（`</|DSML|tag>` → `<|DSML|/tag>`）
   - タグ境界周辺の空白

2. **複数のタグ形式をサポート**:
   - `<|DSML|param>`と`<|DSML|invoke_arg>`（パラメータタグ）
   - 空の値用の自己終了タグ
   - ネストされたinvokeブロック

3. **ツール呼び出しを標準形式に抽出**:
```ruby
{
  "id" => "call_#{SecureRandom.hex(12)}",
  "type" => "function",
  "function" => {
    "name" => "write_file",
    "arguments" => '{"filename":"test.txt","content":"Hello World"}'
  }
}
```

**関連コード**: `deepseek_helper.rb`の700-900行目

### 2. 不正なDSML検出と自動リトライ

**問題**: DeepSeekは、特に終了タグなしで開始タグを繰り返し出力する無限ループパターンで、不完全または不正なDSMLを生成することがあります。

**検出パターン**:
```ruby
dsml_invoke_count = content.scan(/<\|DSML\|invoke/).length
dsml_close_invoke_count = content.scan(/<\|DSML\|\/invoke>/).length
dsml_function_calls_count = content.scan(/<\|DSML\|function_calls>/).length

is_malformed = (dsml_invoke_count > 3 && dsml_close_invoke_count == 0) ||
               (dsml_function_calls_count > 2)
```

**自動リトライメカニズム**:
- 指数バックオフ付きで最大4回リトライ（1秒、2秒、3秒、4秒）
- UIにリトライ進捗を表示：`<i class='fas fa-redo'></i> RETRYING TOOL CALL (X/4)`
- セッション履歴を汚染せずにサイレントリトライ
- 最大リトライ後、ユーザーにエラーメッセージを返す

**関連コード**: `deepseek_helper.rb`の788-825行目

### 3. Reasonerモデルのツール呼び出しサポート

**背景**: V3.2以降、`deepseek-reasoner`はツール呼び出しをサポートしています（以前はサポートしていませんでした）。

**実装**:
```ruby
if obj["model"].include?("reasoner")
  body.delete("temperature")
  body.delete("presence_penalty")
  body.delete("frequency_penalty")
  # 注意：ReasonerはV3.2以降ツール呼び出しをサポート
  # toolsとtool_choiceが存在する場合は保持

  body["messages"] = body["messages"].map do |msg|
    msg["content"] = msg["content"]&.sub(/---\n\n/, "") || msg["content"]
    msg
  end
end
```

**重要ポイント**:
- Temperature と penalty パラメータは削除（reasonerではサポートされていない）
- tools と tool_choice は保持（以前のバージョンとは異なる）
- 推論セパレータマーカー用の特別なコンテンツクリーンアップ

**関連コード**: `deepseek_helper.rb`の427-439行目

### 4. ツール呼び出し時のContentフィールド処理

**問題**: DeepSeek APIは、アシスタントメッセージに`content`と`tool_calls`の両方が存在する場合、`duplicate field 'content'`エラーを返します。

**解決策**: tool_callsが存在する場合、`content`を`nil`に設定：
```ruby
res = {
  "role" => "assistant",
  "content" => nil,  # DeepSeek APIはtool_calls存在時にcontentがnull/空であることを要求
  "tool_calls" => tools_data.map do |tool|
    {
      "id" => tool["id"],
      "type" => "function",
      "function" => tool["function"]
    }
  end
}
```

**注意**: これはMistral（contentフィールドが必須）や他のプロバイダーとは異なります。各APIには異なる要件があります。

**関連コード**: `deepseek_helper.rb`の1109-1122行目

### 5. 関数呼び出しのStrictモード

**パターン**: DeepSeekは強化されたスキーマ検証のためのstrictモードをサポートしています。

```ruby
def use_strict_mode?(settings)
  settings.dig("features", "strict_mode") == true
end

def convert_to_strict_tools(tools)
  tools.map do |tool|
    tool["function"]["strict"] = true
    tool["function"]["parameters"]["additionalProperties"] = false
    tool
  end
end
```

**動作**:
- 有効にすると、関数定義に`strict: true`を追加
- パラメータスキーマに`additionalProperties: false`を設定
- より良い検証を提供するが、より制限的になる可能性がある

**注意**: ベータAPI（`/beta`）のstrictモードにはスキーマ検証の問題があるため、信頼性のために標準APIを使用してください。

**関連コード**: `deepseek_strict_mode_spec.rb`（225行のテスト）

### 6. 推論コンテンツの抽出

**パターン**: `deepseek-reasoner`レスポンスから推論コンテンツを抽出。

```ruby
def extract_reasoning_content(response)
  response.dig("choices", 0, "message", "reasoning_content")
end
```

**表示**:
- 推論コンテンツはUIで折りたたみ可能なパネルに表示
- メインレスポンスコンテンツとは別
- フラグメント結合によるストリーミングをサポート

**SSOT設定**:
```javascript
// model_spec.js
"deepseek-reasoner": {
  "supports_reasoning_content": true,
  "reasoning_content_field": "reasoning_content"
}
```

**関連ドキュメント**: `docs_dev/ruby_service/thinking_reasoning_display.md`

### 7. タイムアウト設定

DeepSeek操作は、特に推論モデルでは長時間実行される可能性があります：

```ruby
DEEPSEEK_OPEN_TIMEOUT = ENV.fetch("DEEPSEEK_OPEN_TIMEOUT", 10).to_i
DEEPSEEK_READ_TIMEOUT = ENV.fetch("DEEPSEEK_READ_TIMEOUT", 600).to_i
DEEPSEEK_WRITE_TIMEOUT = ENV.fetch("DEEPSEEK_WRITE_TIMEOUT", 120).to_i
```

**環境変数**:
- `DEEPSEEK_OPEN_TIMEOUT`: 接続タイムアウト（デフォルト：10秒）
- `DEEPSEEK_READ_TIMEOUT`: レスポンス読み取りタイムアウト（デフォルト：600秒 / 10分）
- `DEEPSEEK_WRITE_TIMEOUT`: リクエスト書き込みタイムアウト（デフォルト：120秒）

## アプリ固有の考慮事項

### Research Assistant（DeepSeek）

DeepSeek版のResearch Assistantは意図的に簡素化されています：
- 複雑なツールシーケンスを避けるための**シンプルなシステムプロンプト**
- ツールループ問題を防ぐため**monadicモード無効**
- 複雑なエージェントパターンの代わりにウェブ検索に**Tavilyを使用**

```ruby
# research_assistant_deepseek.mdsl
# 注意：ツールループ問題のためDeepSeekではmonadicモードを無効化
```

### Coding Assistant（DeepSeek）

より信頼性の高いツール呼び出しのため、デフォルトで`deepseek-reasoner`を使用：
```ruby
llm do
  provider "deepseek"
  # より信頼性の高いツール呼び出しのためReasonerをデフォルトに
  # Chatは高速だが、ファイル操作でDSMLフォーマットの問題が発生する可能性あり
  model ["deepseek-reasoner", "deepseek-chat"]
end
```

## トラブルシューティング

### よくある問題

1. **無限DSMLループ**
   - 症状：レスポンスが完了せずにDSMLタグを生成し続ける
   - 解決策：自動リトライメカニズムがほとんどのケースを処理；ログでリトライ回数を確認

2. **ファイル書き込み失敗**
   - 症状：ファイル操作が繰り返し失敗
   - 原因：特殊文字のDSMLエスケープ問題
   - 解決策：`deepseek-reasoner`モデルを使用；ファイル内容を簡素化

3. **ツール呼び出しが認識されない**
   - 症状：モデルがDSMLを出力するが、ツールが実行されない
   - 原因：処理されていないDSML形式のバリエーション
   - 解決策：EXTRA_LOGGINGを有効にして生のDSMLを確認；新しいパターンを報告

### デバッグ

生のDSML出力を確認するために追加ログを有効化：
```bash
# ~/monadic/config/env で設定
EXTRA_LOGGING=true
```

ログで確認：
- `[DeepSeekHelper] Raw DSML content:` - パース前の元のDSML
- `[DeepSeekHelper] Parsed tools:` - 抽出されたツール呼び出し
- `RETRYING TOOL CALL` - 自動リトライ進行中

## テスト

関連テストファイル：
- `spec/unit/deepseek_reasoning_spec.rb` - 推論コンテンツ抽出
- `spec/lib/monadic/adapters/vendors/deepseek_strict_mode_spec.rb` - Strictモード（225行）
- `spec/integration/provider_matrix/all_providers_all_apps_spec.rb` - 統合テスト

DeepSeek固有のテスト実行：
```bash
PROVIDERS=deepseek RUN_API=true bundle exec rspec spec/integration/provider_matrix/
```

## SSOT移行状況

| 機能 | 現在の場所 | SSOTフィールド | 状況 |
|---------|-----------------|------------|--------|
| 推論コンテンツ | ヘルパーコード | `supports_reasoning_content` | ✅ 移行済み |
| コンテキストウィンドウ | ヘルパーコード | `context_window` | ✅ 移行済み |
| ツール機能 | ヘルパーコード | `tool_capability` | ✅ 移行済み |
| Strictモード | ヘルパーコード | N/A | 該当なし（ランタイム設定） |
| DSMLパース | ヘルパーコード | N/A | プロバイダー固有、SSOTには不適切 |
