# ストリーミングベストプラクティス

このドキュメントは、AIプロバイダー全体でストリーミングレスポンスを実装・修正する際に発見された重要なパターンと落とし穴を記録しています。

## コアストリーミングパターン

すべてのベンダーヘルパーは、`HTTP::Response::Body`を使用した一貫したストリーミングパターンを使用する必要があります：

```ruby
# 正しい: ストリーミングレスポンスボディに.eachを使用
res.each do |chunk|
  chunk = chunk.force_encoding("UTF-8")
  buffer << chunk
  # ... チャンクを処理
end

# 誤り: .each_lineを使用しない（HTTP::Response::Bodyにこのメソッドは存在しない）
res.each_line do |chunk|  # ❌ NoMethodError
  # ...
end

# 誤り: 文字列に変換しない（ストリーミング機能が失われる）
process_json_data(res: res.body.to_s)  # ❌ レスポンス全体がバッファリングされる
```

**重要な原則**: 処理関数には`res.body.to_s`ではなく`res.body`を直接渡します。`.to_s`変換により、処理前にレスポンス全体がバッファリングされ、ストリーミングの目的が損なわれます。

## プロバイダー固有のパターン

### Perplexity: 最初のチャンクに含まれる引用

**重要**: Perplexityは**最初のレスポンスチャンク**にすべての引用を送信し、段階的または最後のチャンクには含まれません。

```ruby
# 最初のチャンクから引用を保存
stored_citations = nil

res.each do |chunk|
  # ...JSONをパース...

  # 最初のチャンクからのみ引用を取得
  if !stored_citations && json["citations"]
    stored_citations = json["citations"]
  end
end

# 最終レスポンスにはstored_citationsを使用し、最後のチャンクのjson["citations"]は使用しない
citations = stored_citations  # ✓ 正しい
citations = json["citations"]  # ❌ nilまたは空の配列になる可能性
```

**理由**: API設計がメタデータを前もって送信するため。最後のチャンクで`json["citations"]`にアクセスするとnilまたは空の配列が返されます。

### Claude: コンテンツブロックイベントとWeb検索

**重要**: ClaudeのWeb検索は複数のコンテンツブロック（検索結果/引用ごとに1つ）を返します。各`content_block_stop`イベントで改行を追加すべきではありません。

```ruby
# 誤り: Web検索で過剰な改行を引き起こす
if json.dig("type") == "content_block_stop"
  res = { "type" => "fragment", "content" => "\n\n" }  # ❌
  block&.call res
end

# 正しい: content_block_stopイベントを完全にスキップ
# Web検索は複数のブロックを返し、それぞれがこのイベントをトリガーする
# if json.dig("type") == "content_block_stop"
#   # スキップ - Web検索で過剰な改行を引き起こす
# end
```

**理由**: 通常のレスポンスには1つのコンテンツブロックがありますが、Web検索には多数あります。各ブロックの後に`\n\n`を追加すると、ストリーミング中に読みにくい出力になります（最終結果はレスポンスオブジェクトから再レンダリングされるため正しい）。

### DeepSeek: ストリーミング中のフラグメントフィルタリング

**重要**: パターンが検出されたらすべてのフラグメントをブロックしないでください。ストリーミング完了**後**にパターンをチェックします。

```ruby
# 誤り: パターンがマッチした時点で以降のすべてのフラグメントをブロック
if choice["message"]["content"] =~ /tavily_search/
  # これは残りのすべてのフラグメントをブロックする！ ❌
elsif fragment.length > 0
  block&.call fragment_res
end

# 正しい: ストリーミング中は特殊マーカーのみフィルタリング
if fragment.length > 0 && !fragment.match?(/<｜[^｜]+｜>/)
  # 特殊マーカーを含まない限りフラグメントを送信
  block&.call fragment_res  # ✓
end

# ストリーミング完了後に関数呼び出しパターンをチェック（125-158行目）
if content =~ /```json.*"name".*"tavily_search"/m
  # 適切なツール呼び出し形式に変換
end
```

**理由**: 正規表現は現在のフラグメントだけでなく、**蓄積されたメッセージコンテンツ全体**をチェックします。一度マッチすると、以降のすべてのフラグメントがブロックされ、ストリーミングが完全に停止します。

### Gemini: HTTPレスポンスボディのイテレーション

**重要**: `HTTP::Response::Body`には`.each_line`ではなく`.each`を使用します。

```ruby
# 正しい
process_json_data(res: res.body)  # ボディを直接渡す

# process_json_data内で:
res.each do |chunk|  # ✓ .eachを使用
  # ...
end

# 誤り
res.each_line do |chunk|  # ❌ NoMethodError: undefined method 'each_line'
  # ...
end
```

**理由**: `HTTP::Response::Body`は`each_line`を実装していません。他のすべてのプロバイダー（DeepSeek、Perplexity、Claude）は`.each`を正常に使用しています。

## フラグメントシーケンシング

適切なフラグメント順序とデバッグのために、シーケンス番号とタイムスタンプを含めます：

```ruby
fragment_sequence = 0

if fragment.length > 0
  res = {
    "type" => "fragment",
    "content" => fragment,
    "sequence" => fragment_sequence,
    "timestamp" => Time.now.to_f
  }
  fragment_sequence += 1
  block&.call res
end
```

これにより以下を識別できます：
- 順序が狂ったフラグメント
- 欠落したフラグメント
- 重複したフラグメント
- タイミングの問題

## ストリーミング問題のテスト

ストリーミング問題をデバッグする際：

1. **EXTRA_LOGGINGを有効化**: `~/monadic/config/env`で`EXTRA_LOGGING=true`を設定
2. **チャンク受信を確認**: チャンクが到着していることを確認（`chunk_count`をログ）
3. **フラグメント送信を確認**: フラグメントがUIに送信されていることを確認（`block&.call`前にログ）
4. **ストリーミングと最終結果を比較**: 最終結果は常にレスポンスオブジェクトから再レンダリングされる
5. **ブロック条件を探す**: フラグメント送信を妨げる条件をチェック

一般的な症状：
- **ストリーミングなし、最終結果は正しい**: フラグメントがブロックされている（DeepSeekパターン）
- **ストリーミング動作、最終結果が誤り**: 蓄積中のデータ損失（Perplexity引用）
- **ストリーミング中の過剰な改行**: フラグメント内の余分なコンテンツ（Claudeコンテンツブロック）
- **レスポンスボディでのNoMethodError**: 誤ったイテレーションメソッド（Gemini each_line）

## 関連ドキュメント

- `docs_dev/ruby_service/thinking_reasoning_display.md` - 推論/思考コンテンツの処理
- `docs_dev/developer/code_structure.md` - ベンダーヘルパーアーキテクチャ
- `CLAUDE.md` - プロバイダー独立性要件
