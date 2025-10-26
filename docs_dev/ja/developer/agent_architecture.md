# エージェントアーキテクチャ

## 概要

Monadic Chatは、複雑なコード生成タスクのためのエージェントアーキテクチャパターンを実装しています。このパターンでは、メインの会話モデルが専用のコード生成モデルに特化したタスクを委譲します。

## サポートされているエージェントパターン

### GPT-5-Codexエージェント（OpenAI）

**メインモデル**: GPT-5
**コード生成モデル**: GPT-5-Codex

**このパターンを使用するアプリ**:
- Code Interpreter OpenAI
- Coding Assistant OpenAI
- Jupyter Notebook OpenAI
- Research Assistant OpenAI

**動作方法**:
1. GPT-5がユーザーインタラクションとツールオーケストレーションを処理
2. 複雑なコード生成が必要な場合、`gpt5_codex_agent`関数が呼び出される
3. GPT-5-Codexが`/v1/responses`エンドポイントを使用してアダプティブ推論で最適化されたコードを生成
4. 結果がGPT-5に返され、会話に統合される

### Grok-Codeエージェント（xAI）

**メインモデル**: `grok-4-fast-reasoning`または`grok-4-fast-non-reasoning`
**コード生成モデル**: `grok-code-fast-1`

**このパターンを使用するアプリ**:
- Code Interpreter Grok
- Coding Assistant Grok
- Jupyter Notebook Grok
- Research Assistant Grok

**動作方法**:
1. `grok-4-fast-reasoning`または`grok-4-fast-non-reasoning`がユーザーインタラクションとツールオーケストレーションを処理
2. 複雑なコード生成が必要な場合、`grok_code_agent`関数が呼び出される
3. `grok-code-fast-1`が最適化されたコードを生成
4. 結果がGrok-4に返され、会話に統合される

## 実装詳細

### モジュール構造

```ruby
# GPT-5-Codexエージェント
module Monadic::Agents::GPT5CodexAgent
  def has_gpt5_codex_access?
    # OpenAI APIキーをチェック
  end

  def call_gpt5_codex(prompt:, app_name:, timeout:)
    # responses API経由でGPT-5-Codexを呼び出し
  end

  def build_codex_prompt(task:, context:, current_code:)
    # 構造化されたプロンプトを構築
  end
end

# Grok-Codeエージェント
module Monadic::Agents::GrokCodeAgent
  def has_grok_code_access?
    # xAI APIキーをチェック
  end

  def call_grok_code(prompt:, app_name:, timeout:)
    # Grok-Code-Fast-1を呼び出し
  end

  def build_grok_code_prompt(task:, context:, current_code:)
    # 構造化されたプロンプトを構築
  end
end
```

### MDSLでのツール定義

```ruby
# coding_assistant_openai.mdslからの例
define_tool "gpt5_codex_agent", "Call GPT-5-Codex agent for complex coding tasks" do
  parameter :task, "string", "Description of the code generation task", required: true
  parameter :context, "string", "Additional context about the project", required: false
  parameter :files, "array", "Array of file objects with path and content", required: false
end

# coding_assistant_grok.mdslからの例
define_tool "grok_code_agent", "Call Grok-Code-Fast-1 agent for complex coding tasks" do
  parameter :task, "string", "Description of the code generation task", required: true
  parameter :context, "string", "Additional context about the project", required: false
  parameter :files, "array", "Array of file objects with path and content", required: false
end
```

## アクセス制御

### GPT-5-Codexアクセス
- すべてのOpenAI APIキー保持者がGPT-5-Codexにアクセス可能
- 追加のモデルリストチェックは不要
- `OPENAI_API_KEY`の存在によってアクセスが決定される

### Grok-Codeアクセス
- すべてのxAI APIキー保持者がGrok-Code-Fast-1にアクセス可能
- `XAI_API_KEY`の存在によってアクセスが決定される

## フォールバック動作

エージェントアクセスが利用できない場合:
1. 説明付きのエラーメッセージが返される
2. 適切なAPIキーを設定するよう提案される
3. アプリがメインモデルで続行することを示すフォールバックメッセージが表示される

## 設定

### 環境変数
```bash
# OpenAI
OPENAI_API_KEY=sk-...

# xAI
XAI_API_KEY=xai-...
```

### タイムアウト設定
- デフォルトタイムアウト: 120秒
- Code Interpreterアプリは複雑なアルゴリズムのためにより長いタイムアウト（360秒）を使用する場合がある
- 環境変数で設定可能: `GPT5_CODEX_TIMEOUT` / `GROK_CODE_TIMEOUT`

## テスト

両方のエージェントモジュールにユニットテストが提供されています:
- `spec/unit/agents/gpt5_codex_agent_spec.rb`
- `spec/unit/agents/grok_code_agent_spec.rb`

テストカバレッジ:
- アクセスチェック
- プロンプト構築
- API呼び出し
- エラーハンドリング
- タイムアウト動作

## ベストプラクティス

1. **複雑なコード生成にはエージェントを使用** - 簡単なスニペットにはエージェントを呼び出さない
2. **コンテキストを提供** - プロジェクトや要件に関する関連コンテキストを含める
3. **タイムアウトを適切に処理** - 複雑なコード生成には時間がかかる場合がある
4. **アクセスチェックをキャッシュ** - アクセス状態はキャッシュされ、繰り返しチェックを避ける
5. **デバッグのためにログを記録** - 詳細なエージェントアクティビティログのために`EXTRA_LOGGING`を有効にする
