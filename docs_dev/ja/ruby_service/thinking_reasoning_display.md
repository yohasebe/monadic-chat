# 思考/推論プロセス表示実装

このドキュメントは、Monadic Chatが様々なAIプロバイダーからの思考/推論プロセスをユーザーインターフェースに表示する方法を説明します。

## 概要

いくつかのAIプロバイダーは、内部の推論または思考プロセスを公開するモデルを提供しています。Monadic Chatはこのコンテンツを取得し、メインのレスポンスとは別に表示することで、ユーザーがモデルがどのように答えに到達したかを理解できるようにします。

## サポートされているプロバイダー

### プロバイダー固有の実装

| プロバイダー | モデル | 形式 | 表示名 |
|----------|--------|--------|--------------|
| **OpenAI** | o1、o3シリーズ | フィールドベース（`reasoning_content`） | Reasoning |
| **Anthropic (Claude)** | Sonnet 4.5+ | コンテンツブロック（`type: "thinking"`） | Thinking |
| **DeepSeek** | deepseek-reasoner、deepseek-r1 | フィールドベース（`reasoning_content`） | Reasoning |
| **Gemini** | gemini-2.0-flash-thinking-exp | `thought: true`フラグ付きパーツ | Thinking |
| **Grok** | すべてのモデル | フィールドベース（`reasoning_content`） | Reasoning |
| **Mistral** | すべてのモデル | フィールドベース（`reasoning_content`） | Reasoning |
| **Cohere** | すべてのモデル | JSON形式（`content["thinking"]`） | Thinking |
| **Perplexity** | sonar-reasoning-pro | デュアル形式（JSON + タグ） | Thinking |

## 実装パターン

### フィールドベースパターン（OpenAI、DeepSeek、Grok、Mistral）

これらのプロバイダーは、ストリーミングデルタ内の専用フィールドに推論コンテンツを含めます：

```ruby
# デルタから抽出
reasoning = json.dig("choices", 0, "delta", "reasoning_content")

unless reasoning.to_s.strip.empty?
  reasoning_content << reasoning

  # リアルタイムでUIに送信
  res = {
    "type" => "reasoning",
    "content" => reasoning
  }
  block&.call res
end

# 最終レスポンスに追加
if reasoning_content && !reasoning_content.empty?
  result["choices"][0]["message"]["reasoning"] = reasoning_content.join("\n\n")
end
```

### コンテンツブロックパターン（Claude）

Claudeは明示的なタイプを持つ構造化されたコンテンツブロックを使用します：

```ruby
# 思考ブロック開始を検出
if event["type"] == "content_block_start"
  current_block_type = event.dig("content_block", "type")
  if current_block_type == "thinking"
    thinking = event.dig("content_block", "thinking")
    # 保存してUIに送信
  end
end

# 思考デルタを処理
if event["type"] == "content_block_delta"
  if event.dig("delta", "type") == "thinking_delta"
    thinking = event.dig("delta", "thinking")
    # 保存してUIに送信
  end
end
```

### パーツベースパターン（Gemini）

Geminiはコンテンツパーツに`thought`フラグを含めます：

```ruby
parts = json.dig("candidates", 0, "content", "parts") || []
parts.each do |part|
  if part["thought"]
    thoughts << part["text"]

    # UIに送信
    res = {
      "type" => "thinking",
      "content" => part["text"]
    }
    block&.call res
  end
end
```

### JSON形式パターン（Cohere）

Cohereは単語レベルのフラグメントとして思考をJSON構造で送信します：

```ruby
if content && content.is_a?(Hash)
  if thinking_text = content["thinking"]
    unless thinking_text.strip.empty?
      thinking << thinking_text

      res = {
        "type" => "thinking",
        "content" => thinking_text
      }
      block&.call res
    end
  end
end

# セパレータなしで結合（単語レベルフラグメント）
if thinking_content && !thinking_content.empty?
  response[0]["choices"][0]["message"]["thinking"] = thinking_content.join("")
end
```

### デュアル形式パターン（Perplexity）

PerplexityはJSON形式とXMLスタイルタグの両方をサポートします：

```ruby
# タグベース形式の状態を追跡
inside_think_tag = false

# JSON形式検出
if content && content.is_a?(Hash)
  if thinking_text = content["thinking"]
    # Cohereのように処理
  end
elsif content
  # タグ形式: <think>...</think>
  fragment = content.to_s

  # タグ境界を追跡
  if !inside_think_tag && fragment.include?('<think>')
    inside_think_tag = true
  end

  if inside_think_tag && fragment.include?('</think>')
    inside_think_tag = false
  end

  # 思考タグ内のフラグメントを抑制
  if inside_think_tag || fragment.include?('<think>') || fragment.include?('</think>')
    fragment = ""
  end

  # 完全な思考ブロックを抽出
  fragment.scan(/<think>(.*?)<\/think>/m) do |match|
    thinking_text = match[0].strip
    unless thinking_text.empty?
      thinking << thinking_text

      res = {
        "type" => "thinking",
        "content" => thinking_text
      }
      block&.call res
    end
  end
end
```

## フロントエンド表示

### ストリーミング表示（一時カード）

ストリーミング中、思考/推論コンテンツは一時カードに表示されます：

```javascript
// temp-reasoning-cardを作成
tempReasoningCard = $(`
  <div id="temp-reasoning-card" class="card mt-3 streaming-card border-info">
    <div class="card-header p-2 ps-3 bg-info bg-opacity-10">
      <div class="fs-6 card-title mb-0 text-muted">
        <span><i class="fas fa-brain"></i></span> <span class="fw-bold">${titleText}</span>
      </div>
    </div>
    <div class="card-body">
      <div class="card-text small text-muted"></div>
    </div>
  </div>
`);

// 思考コンテンツを追加
if (json.type === "thinking" || json.type === "reasoning") {
  tempReasoningCard.find('.card-text').append(json.content);
}
```

### 最終表示（折りたたみ可能トグル）

ストリーミング完了後、思考コンテンツは折りたたみ可能トグルに移動します：

```javascript
let thinkingHtml = `
  <div class="thinking-toggle mt-2">
    <a class="text-decoration-none" data-bs-toggle="collapse" href="#thinking-${index}">
      <i class="fas fa-chevron-right"></i> <span class="fw-bold">${titleText}</span>
    </a>
    <div class="collapse" id="thinking-${index}">
      <div class="card card-body mt-2 small text-muted">
        ${marked.parse(thinking)}
      </div>
    </div>
  </div>
`;
```

## フラグメント処理戦略

### ブロックレベルフラグメント（ほとんどのプロバイダー）

完全な文または段落を送信するプロバイダーは、可読性を保持するために`join("\n\n")`を使用します：

```ruby
reasoning_content.join("\n\n")  # OpenAI、DeepSeek、Grok、Mistral、Gemini、Perplexity
```

### 単語レベルフラグメント（Cohere）

Cohereは個々の単語/トークンを送信するため、直接連結が必要です：

```ruby
thinking_content.join("")  # Cohere
```

### フラグメント抑制（Perplexityタグ形式）

タグ形式を使用する場合、`<think>`タグ内のフラグメントは重複表示を防ぐために抑制する必要があります：

```ruby
# 思考タグ内のすべてのフラグメントを抑制
if inside_think_tag || fragment.include?('<think>') || fragment.include?('</think>')
  fragment = ""
end
```

これにより、ストリーミング中に思考コンテンツが通常の一時カードに表示されるのを防ぎます。

## 設定

### モデル仕様

思考/推論をサポートするモデルは、`model_spec.js`でフラグを立てる必要があります：

```javascript
{
  name: "o1",
  provider: "openai",
  supportsReasoning: true  // 推論機能を示す
}
```

### 拡張思考（Claude）

Claudeの拡張思考モードには明示的なパラメータが必要です：

```ruby
if model_name.include?("sonnet")
  params["thinking"] = {
    "type" => "enabled",
    "budget_tokens" => 10000
  }
end
```

### 思考設定（Gemini）

Geminiには思考モード設定が必要です：

```ruby
config = {
  "thinkingConfig" => {
    "thinkingMode" => "THINKING_MODE_ENABLED"
  }
}
```

## テスト

テストファイルは、各プロバイダーの抽出、集約、表示ロジックを検証します：

- `spec/unit/openai_reasoning_spec.rb`（14例）
- `spec/unit/claude_thinking_spec.rb`（15例）
- `spec/unit/deepseek_reasoning_spec.rb`（14例）
- `spec/unit/gemini_thinking_spec.rb`（14例）
- `spec/unit/grok_reasoning_spec.rb`（12例）
- `spec/unit/mistral_reasoning_spec.rb`（12例）
- `spec/unit/cohere_thinking_spec.rb`（12例）
- `spec/unit/perplexity_thinking_spec.rb`（15例）

テストを実行：

```bash
rake spec_unit
```

## デバッグ

### 追加ログを有効化

`~/monadic/config/env`で設定：

```bash
EXTRA_LOGGING=true
```

### サーバーデバッグモード

デバッグにローカルRubyを使用（Dockerコンテナではない）：

```bash
rake server:debug
```

### 一般的な問題

1. **temp-reasoning-cardが欠落**: ベンダーヘルパーから`type: "thinking"`または`type: "reasoning"`メッセージが送信されていることを確認

2. **コンテンツの重複**: フラグメント抑制が正しく機能していることを確認（特にタグベース形式）

3. **誤った結合戦略**: 単語レベルとブロックレベルのフラグメント処理を確認

4. **分割タグが抽出されない**: 不完全なタグペアに対するバッファ蓄積ロジックが実装されていることを確認

## 関連ドキュメント

- `docs_dev/developer/reasoning_context_guidance.md` - GPT-5推論コンテキスト設定
- `docs/updates/reasoning_effort_changes.md` - 推論努力パラメータ更新
- `docs_dev/websocket_progress_broadcasting.md` - WebSocketメッセージブロードキャスト
