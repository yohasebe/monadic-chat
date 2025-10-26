# システムプロンプトインジェクションアーキテクチャ

## 概要

Monadic Chatは、統一されたプロンプトインジェクションシステム（`SystemPromptInjector`）を使用して、ランタイム条件に基づいてAIプロンプトを動的に拡張します。このシステムは、以前9つのベンダーヘルパーファイルとwebsocket.rbに分散していたインジェクションロジックを置き換えました。

## アーキテクチャ

### コアモジュール

**場所**: `docker/services/ruby/lib/monadic/utils/system_prompt_injector.rb`

`SystemPromptInjector`モジュールは以下を提供します：
- 優先順位付けを持つルールベースのインジェクションシステム
- システムメッセージとユーザーメッセージの個別コンテキスト
- 適切なエラーハンドリング
- 一貫したセパレーター管理

### 2つのインジェクションコンテキスト

1. **システムコンテキスト** (`:system`)
   - 会話開始時に1回適用
   - 初期システムメッセージを変更
   - 現在5つのアクティブなルールを持つ

2. **ユーザーコンテキスト** (`:user`)
   - 各ユーザー入力に適用
   - ユーザーメッセージに指示を追加
   - 現在1つのアクティブなルールを持つ

## 現在のインジェクションルール

### システムコンテキストルール（優先順位順）

| 優先順位 | ルール名 | 条件 | 目的 |
|----------|-----------|-----------|---------|
| 100 | `language_preference` | ユーザーが言語を設定（"auto"以外） | レスポンス言語を強制 |
| 80 | `websearch` | ウェブサーチ有効 + 非推論モデル | ウェブ検索指示を追加 |
| 60 | `stt_diarization_warning` | STTモデルに"diarize"を含む | 話者ラベル解釈について警告 |
| 50 | `mathjax` | MathJax有効 | LaTeX/MathJaxフォーマット指示を追加 |
| 40 | `system_prompt_suffix` | オプションでサフィックスが提供される | カスタムシステムプロンプトサフィックスを追加 |

### ユーザーコンテキストルール（優先順位順）

| 優先順位 | ルール名 | 条件 | 目的 |
|----------|-----------|-----------|---------|
| 10 | `prompt_suffix` | 設定でサフィックスが提供される | 各ユーザー入力に指示を追加 |

## ルール構造

各インジェクションルールは4つのコンポーネントを持つハッシュです：

```ruby
{
  name: :rule_name,           # シンボル識別子
  priority: 100,              # 高い = 出力で早い
  condition: ->(session, options) {
    # true/falseを返すラムダ
    # sessionとoptionsにアクセス可能
  },
  generator: ->(session, options) {
    # インジェクトするテキストを返すラムダ
    # conditionがtrueの場合のみ呼び出される
  }
}
```

## 新しいインジェクションルールの追加

### ステップ1: プロンプトコンテンツの定義

`system_prompt_injector.rb`の先頭でプロンプトコンテンツの定数を追加します：

```ruby
# コンテンツにバックスラッシュが含まれる場合は<<~'PROMPT'（シングルクォート）を使用
MY_FEATURE_PROMPT = <<~'PROMPT'.strip
  ここにプロンプトコンテンツを記述。
  バックスラッシュを文字通り保持するにはシングルクォートを使用。
PROMPT
```

### ステップ2: ルールの追加

適切な配列にルールを追加します：

```ruby
# システムコンテキスト用
SYSTEM_INJECTION_RULES = [
  # ... 既存のルール ...
  {
    name: :my_feature,
    priority: 45,  # 希望する順序に基づいて選択
    condition: ->(session, _options) {
      # セッションパラメーターまたはランタイム設定をチェック
      session[:parameters]&.[]("my_feature") == true
    },
    generator: ->(_session, _options) {
      MY_FEATURE_PROMPT
    }
  }
].freeze

# ユーザーコンテキスト用
USER_INJECTION_RULES = [
  # ... 既存のルール ...
  {
    name: :my_user_feature,
    priority: 15,
    condition: ->(_session, options) {
      !options[:my_setting].to_s.empty?
    },
    generator: ->(_session, options) {
      options[:my_setting].to_s.strip
    }
  }
].freeze
```

### ステップ3: ベンダーヘルパー呼び出しの更新

統一されたシステムは既に9つのベンダーヘルパーすべてに統合されています。新しいオプションを渡す場合を除き、変更は不要です。

新しいオプションを渡す必要がある場合：

```ruby
augmented_prompt = Monadic::Utils::SystemPromptInjector.augment(
  base_prompt: initial_prompt,
  session: session,
  options: {
    websearch_enabled: websearch_enabled,
    # 新しいオプションをここに追加
    my_setting: obj["my_setting"]
  }
)
```

### ステップ4: テストの追加

`docker/services/ruby/spec/unit/utils/system_prompt_injector_spec.rb`にテストケースを追加します：

```ruby
context 'with my feature enabled' do
  it 'includes my feature prompt' do
    session = {
      parameters: { "my_feature" => true }
    }
    options = {}

    result = described_class.build_injections(session: session, options: options)

    expect(result.length).to eq(1)
    expect(result[0][:name]).to eq(:my_feature)
    expect(result[0][:content]).to include('expected content')
  end

  it 'excludes my feature when disabled' do
    session = {
      parameters: { "my_feature" => false }
    }
    options = {}

    result = described_class.build_injections(session: session, options: options)

    expect(result).to be_empty
  end
end
```

### ステップ5: 優先順位テストの更新

"with multiple conditions met"テストを更新して新しいルールを含めます：

```ruby
expect(result.length).to eq(6)  # カウントをインクリメント
# 優先順位順にルールの期待値を追加
expect(result[3][:name]).to eq(:my_feature)  # 優先順位に基づいてインデックスを調整
```

## 使用例

### 基本的なシステムプロンプト拡張

```ruby
augmented = Monadic::Utils::SystemPromptInjector.augment(
  base_prompt: "You are a helpful assistant.",
  session: session,
  options: {
    websearch_enabled: true,
    websearch_prompt: "Search the web when needed.",
    system_prompt_suffix: "Always be concise."
  }
)
```

### ユーザーメッセージの拡張

```ruby
augmented = Monadic::Utils::SystemPromptInjector.augment_user_message(
  base_message: "What is the weather?",
  session: session,
  options: {
    prompt_suffix: "Respond in one sentence."
  }
)
```

### 手動インジェクション構築

```ruby
injections = Monadic::Utils::SystemPromptInjector.build_injections(
  session: session,
  options: options,
  context: :system
)

# ハッシュの配列を返す: [{ name: :rule_name, content: "text" }, ...]
```

## 実装詳細

### 優先順位付け

ルールは降順の優先順位で実行されます（100 → 10）。これにより以下が保証されます：
- 言語設定が最初に適用される（最も基本的）
- 機能固有のプロンプトが中間
- ユーザーカスタマイズが最後（最も具体的）

### エラーハンドリング

システムには適切なエラーハンドリングが含まれています：
- 条件評価が失敗した場合、ルールはスキップされる
- ジェネレーターが失敗した場合、ルールはスキップされる
- `EXTRA_LOGGING=true`の場合、エラーがログに記録される
- 空のコンテンツは自動的にフィルタリングされる

### セパレーター管理

デフォルトセパレーター：
- システムコンテキスト: `"\n\n---\n\n"`（明確に区切られたセクション）
- ユーザーコンテキスト: `"\n\n"`（シンプルな段落区切り）

カスタムセパレーターを指定可能：

```ruby
augmented = SystemPromptInjector.augment(
  base_prompt: prompt,
  session: session,
  options: options,
  separator: "\n\n"  # カスタムセパレーター
)
```

### 定数内の文字列エスケープ

**重要**: バックスラッシュを含むプロンプト定数（例：LaTeX/MathJax）を定義する場合、シングルクォートのヒアドキュメントを使用してください：

```ruby
# 誤 - バックスラッシュが解釈される
MY_LATEX_PROMPT = <<~PROMPT
  Use \frac{a}{b} for fractions.
PROMPT
# 結果: "Use rac{a}{b}" (バックスラッシュが消費される!)

# 正 - バックスラッシュが文字通り保持される
MY_LATEX_PROMPT = <<~'PROMPT'
  Use \frac{a}{b} for fractions.
PROMPT
# 結果: "Use \frac{a}{b}" (バックスラッシュが保持される!)
```

## 移行履歴

### 以前：分散実装

2025-01以前、プロンプトインジェクションロジックは以下に分散していました：
- 9つのベンダーヘルパーファイル（`*_helper.rb`）：約200行の重複コード
- `websocket.rb`：MathJax用の追加インジェクション（約45行）

問題点：
- 新機能には9つの個別ファイルへの変更が必要
- ベンダー間で一貫性のない実装
- 異なるセパレーターとインジェクションポイント
- 保守とテストが困難

### 以後：統一されたシステム

現在の実装（2025-01）：
- `system_prompt_injector.rb`内の単一の信頼できる情報源
- 9つのベンダーすべてに自動的に利用可能
- 一貫した動作とテスト
- 新機能には約10行のコード（1つのルール定義）が必要

### 移行プロセス

9つのベンダーヘルパーすべてがリファクタリングされました：
1. OpenAI Helper
2. Claude Helper
3. Gemini Helper
4. Mistral Helper
5. DeepSeek Helper
6. Cohere Helper
7. Grok Helper
8. Perplexity Helper
9. Ollama Helper

各ヘルパーは現在以下を使用します：
```ruby
require_relative "../../utils/system_prompt_injector"

# システムメッセージの拡張
augmented_prompt = Monadic::Utils::SystemPromptInjector.augment(
  base_prompt: initial_prompt,
  session: session,
  options: options
)

# ユーザーメッセージの拡張
augmented_text = Monadic::Utils::SystemPromptInjector.augment_user_message(
  base_message: user_input,
  session: session,
  options: { prompt_suffix: prompt_suffix }
)
```

## 特殊ケース

### MathJaxインジェクション

MathJaxは異なるモードで異なるエスケープを必要とします：
- **通常モード**: シングルバックスラッシュ（`\frac`）
- **Monadic/Jupyterモード**: JSONシリアライゼーションのためのダブルバックスラッシュ（`\\frac`）

MathJaxルールはこれを自動的に処理します：

```ruby
{
  name: :mathjax,
  priority: 50,
  condition: ->(session, _options) {
    session[:parameters]&.[]("mathjax") == true
  },
  generator: ->(session, _options) {
    parts = [MATHJAX_BASE_PROMPT]

    monadic_mode = session[:parameters]&.[]("monadic") == true
    jupyter_mode = session[:parameters]&.[]("jupyter") == true

    if monadic_mode || jupyter_mode
      parts << MATHJAX_MONADIC_PROMPT  # ダブルエスケープ
    else
      parts << MATHJAX_REGULAR_PROMPT  # シングルエスケープ
    end

    parts.join("\n\n")
  }
}
```

### STTダイアライゼーション警告

ダイアライゼーション有効のSTTモデル（例：`gpt-4o-transcribe-diarize`）を使用する場合、AIがラベル付けされた話者の1人（A:、B:、C:）の役割を誤って採用する可能性があります。ダイアライゼーション警告インジェクションはこれを防ぎます：

```ruby
{
  name: :stt_diarization_warning,
  priority: 60,
  condition: ->(session, _options) {
    stt_model = session[:parameters]&.[]("stt_model")
    stt_model && stt_model.to_s.include?("diarize")
  },
  generator: ->(_session, _options) {
    DIARIZATION_STT_PROMPT  # AIに話者の役割を採用しないよう警告
  }
}
```

## テスト

### テストカバレッジ

システムは`docker/services/ruby/spec/unit/utils/system_prompt_injector_spec.rb`で包括的なテストカバレッジを持っています：

- **ユニットテスト**: 各ルールを個別にテスト
- **統合テスト**: 複数のルールを組み合わせてテスト
- **優先順位テスト**: 正しい順序を検証
- **エラーハンドリングテスト**: 適切な劣化
- **エッジケース**: 空文字列、nil値など

現在のテスト数：26例、0失敗

### テストの実行

```bash
# すべてのSystemPromptInjectorテストを実行（docker/services/rubyディレクトリから）
bundle exec rspec spec/unit/utils/system_prompt_injector_spec.rb

# 完全な説明付きで実行
bundle exec rspec spec/unit/utils/system_prompt_injector_spec.rb -fd

# 特定のコンテキストを実行
bundle exec rspec spec/unit/utils/system_prompt_injector_spec.rb -e "with MathJax enabled"
```

## ベストプラクティス

1. **優先順位の割り当て**
   - 将来の挿入を許可するために10-20の間隔を使用
   - 言語設定：100
   - 機能トグル：40-80
   - ユーザーカスタマイズ：10-30

2. **条件チェック**
   - 常に安全なナビゲーション（`&.[]`）を使用
   - nilと空文字列をチェック
   - 明示的にブール値を返す

3. **ジェネレーター関数**
   - `.strip`で空白を削除
   - nil値を適切に処理
   - 静的コンテンツには定数を使用

4. **テスト**
   - 有効状態と無効状態の両方をテスト
   - 複数の条件でテスト
   - エラーケースをテスト（nilセッション、欠落キー）

5. **ドキュメンテーション**
   - 複雑なロジックにインラインコメントを追加
   - ルールを追加する際はこのドキュメントを更新
   - 特殊なエスケープの必要性をドキュメント化

## 関連ファイル

- **実装**: `docker/services/ruby/lib/monadic/utils/system_prompt_injector.rb`
- **テスト**: `docker/services/ruby/spec/unit/utils/system_prompt_injector_spec.rb`
- **ベンダーヘルパー**: `docker/services/ruby/lib/monadic/adapters/vendors/*_helper.rb`
- **言語設定**: `docker/services/ruby/lib/monadic/utils/language_config.rb`
