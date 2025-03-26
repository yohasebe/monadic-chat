# Monadic DSLの内部実装

?> このドキュメントはMonadic DSL (MDSL)の内部実装について詳細な説明を提供します。MDSLの内部動作を理解したい開発者や、その開発に貢献したい方向けの内容です。

## 1. 概要

Monadic DSL (MDSL)は、AI駆動アプリケーションの作成を簡素化するために開発されたRubyベースのドメイン特化言語です。Rubyの言語機能を活用することで、開発者は異なるLLMプロバイダーの複雑さを気にすることなく、宣言的な方法でアプリケーションを定義できます。

### 1.1 MDSLの特徴

#### 1.1.1 宣言的な構文
アプリケーションは`app "名前" do ... end`形式で定義され、様々な設定が階層的に整理され、読みやすい形式で表現されます。

```ruby
app "ChatClaude" do
  description "Anthropic APIを使用したチャットアプリ"
  icon "a"
  system_prompt "あなたは友好的なAIアシスタントです..."
  
  llm do
    provider "anthropic"
    model "claude-3-5-sonnet-20241022"
  end
  
  features do
    easy_submit false
    image true
  end
end
```

#### 1.1.2 プロバイダー抽象化
MDSLはOpenAI、Anthropic (Claude)、Google (Gemini)、Cohere、Mistral、DeepSeek、Perplexity、xAI (Grok) といった様々なLLMプロバイダーの違いを抽象化します。これにより、開発者は簡単にプロバイダーを切り替えたり、わずかな労力で複数のプロバイダー向けに類似のアプリケーションを作成したりできます。

```ruby
# Anthropic/Claude版
app "ChatClaude" do
  llm do
    provider "anthropic"
    model "claude-3-5-sonnet-20241022"
  end
end

# OpenAI版
app "ChatOpenAI" do
  llm do
    provider "openai"
    model "gpt-4o"
  end
end
```

#### 1.1.3 統一されたツール定義
異なるLLMプロバイダーは関数呼び出し（ツール）に異なるフォーマットを要求しますが、MDSLはこれらの違いを隠蔽し、一貫したツール定義構文を提供します。

```ruby
tools do
  define_tool "search_web", "インターネット検索を実行する" do
    parameter "query", "string", "検索クエリ", required: true
    parameter "num_results", "integer", "結果の数", required: false
  end
end
```

#### 1.1.4 Rubyクラスへの変換
DSL定義は実行時に評価され、`MonadicApp`クラスを継承した実際のRubyクラスに変換されます。これにより、DSLの簡潔さと実行時の高機能性を両立しています。

#### 1.1.5 Monadicエラー処理
MDSLは関数型プログラミングの概念を取り入れたモナディックなパターン（`Result`クラスと`bind`/`map`操作）を採用し、エラー処理と状態変換を実現しています。これにより、エラーハンドリングが明示的かつ流れるように連鎖可能になります。

```ruby
# 成功/失敗を表すResultモナド
class Result
  attr_reader :value, :error
  
  def initialize(value, error = nil)
    @value = value
    @error = error
  end
  
  # エラーがあれば処理を中断し、なければ値を変換して新しいResultを返す
  def bind(&block)
    return self if @error
    begin
      block.call(@value)
    rescue => e
      Result.new(nil, e)
    end
  end
  
  # bindの簡易版 - 値を変換してResultでラップ
  def map(&block)
    bind { |value| Result.new(block.call(value)) }
  end
  
  def success?
    !@error
  end
end
```

#### 1.1.6 プロバイダー別フォーマッタ
各プロバイダー用の専用フォーマッタクラスがあり、抽象的なツール定義をプロバイダー固有のJSON形式に変換します。これにより、開発者は実装の詳細を気にせずにツールを定義できます。

## 2. Rubyの言語機能を活用したMDSLの内部実装

MDSLはクリーンで宣言的な構文を実現するために、いくつかのRuby言語機能を活用しています。これらの機能を理解することで、MDSLの内部動作を説明できます。

### 2.1 メタプログラミング

MDSLは`eval`を使ってDSLファイルを実行し、コードをRubyインタプリタに直接解釈させます。これにより`.mdsl`ファイルをRubyコードとして実行でき、DSLのパースと実行はすべて実行時に行われ、柔軟な構文を実現しています。

```ruby
def load_dsl
  # DSLをTOPLEVEL_BINDINGコンテキストで評価
  app_state = eval(@content, TOPLEVEL_BINDING, @file)
rescue => e
  warn "Warning: Failed to evaluate DSL in #{@file}: #{e.message}"
  raise
end
```

一般的に`eval`はセキュリティリスクがあるため、外部からの入力をそのまま評価するのは危険です。しかし、MDSLは内部DSLであり、開発者によって書かれたファイルを実行するために使用され、実行はDockerコンテナ内で行われるため、セキュリティ上の懸念は最小限です。

### 2.2 ブロック構文

Rubyのブロック構文は、コンテキスト固有のスコープ付き設定を可能にします：

```ruby
app "名前" do
  # アプリコンテキスト
  
  llm do
    # LLMコンテキスト
    provider "anthropic"
    model "claude-3-5-sonnet-20241022"
  end
end

# 実装部分
def llm(&block)
  LLMConfiguration.new(@state).instance_eval(&block)
end
```

このブロック構文により、読みやすく保守しやすい階層的な設定が可能になります。

### 2.3 ダイナミックなクラス生成

MDSLは`eval`を使用して文字列定義からRubyクラスを動的に生成します：

```ruby
def self.convert_to_class(state)
  class_def = <<~RUBY
    class #{state.name} < MonadicApp
      include #{helper_module} if defined?(#{helper_module})

      @settings = {
        model: #{state.settings[:model].inspect},
        # その他の設定
      }
    end
  RUBY

  eval(class_def, TOPLEVEL_BINDING, state.name)
end
```

`convert_to_class`メソッドでは、DSLの定義からRubyクラスを動的に生成し、実行時に実際のアプリケーションクラスに変換します。

### 2.4 モジュールとミックスイン

生成されたクラスは、DSLで指定された`provider`プロパティの値に基づいて適切なヘルパーモジュール（`OpenAIHelper`、`ClaudeHelper`など）を含みます。

```ruby
module ToolFormatters
  class AnthropicFormatter
    def format(tool)
      {
        name: tool.name,
        description: tool.description,
        input_schema: { /* ... */ }
      }
    end
  end
  # 他のフォーマッタクラス
end

FORMATTERS = {
  openai: ToolFormatters::OpenAIFormatter,
  anthropic: ToolFormatters::AnthropicFormatter,
  # 他のプロバイダー
}
```

このモジュラー設計により、プロバイダー固有のロジックが柔軟性のために分離されています。

### 2.5 Rubyの柔軟な構文

MDSLは`method_missing`を使用して動的なメソッド処理を行い、未定義のメソッドを処理できるようにし、DSLの表現力を高めています：

```ruby
# 1. LLMConfiguration - パラメータ名のエイリアスを処理
# 例：max_output_tokensをmax_tokensに変換
def method_missing(method_name, *args)
  if PARAMETER_MAP.key?(method_name)
    send(PARAMETER_MAP[method_name], *args)
  else
    super
  end
end

# 2. SimplifiedFeatureConfiguration - 任意の機能フラグを処理
# 例：easy_submit、auto_speech、imageなど
def method_missing(method_name, *args)
  value = args.first.nil? ? true : args.first
  feature_name = FEATURE_MAP[method_name] || method_name
  @state.features[feature_name] = value
end
```

これにより、DSLユーザーは様々な機能を宣言的に指定できます：

```ruby
features do
  easy_submit false   # 既知の機能
  auto_speech false   # 既知の機能
  new_feature true    # 未知の機能も受け付ける
end
```

### 2.6 クロージャーとスコープ

MDSLは`instance_eval`を使用して、ブロックを特定のインスタンスのコンテキストで評価します。これにより、DSLユーザーはローカル変数やメソッドをDSLコンテキスト内で使用できます：

```ruby
def define_tool(name, description, &block)
  tool = ToolDefinition.new(name, description)
  tool.instance_eval(&block) if block_given?
  tool.validate_for_provider(@provider)
  @tools << tool
  tool
end
```

これにより、ツール定義に自然な構文が可能になります：

```ruby
tools do
  define_tool "search", "ウェブ検索" do
    parameter "query", "string", "検索クエリ", required: true
  end
end
```

## 3. プロバイダー設定システム

MDSLの重要なコンポーネントの一つは、各プロバイダーに適切なヘルパーモジュールを識別して設定する方法です：

```ruby
class ProviderConfig
  # プロバイダー情報マッピング
  PROVIDER_INFO = {
    "xai" => {
      helper_module: 'GrokHelper',  # ヘルパーモジュール名
      api_key: 'XAI_API_KEY',
      display_group: 'xAI Grok',
      aliases: ['grok', 'xaigrok']
    },
    # 他のプロバイダー...
  }
  
  def initialize(provider_name)
    @provider_name = provider_name.to_s.downcase.gsub(/[\s\-]+/, "")
    @config = find_provider_config
  end
  
  # ヘルパーモジュール名を取得
  def helper_module
    @config[:helper_module]
  end
  
  private
  
  # 名前またはエイリアスでプロバイダー設定を検索
  def find_provider_config
    # 直接マッチ
    PROVIDER_INFO.each do |key, config|
      return config.merge(standard_key: key) if key == @provider_name
    end
    
    # エイリアスでチェック
    PROVIDER_INFO.each do |key, config|
      return config.merge(standard_key: key) if config[:aliases].include?(@provider_name)
    end
    
    # マッチしない場合はOpenAIをデフォルトに
    PROVIDER_INFO["openai"]
  end
end
```

このシステムにより、ユーザーは様々な名前（例：`anthropic`や`claude`）でプロバイダーを指定でき、システムは適切なヘルパーモジュールを見つけることができます。

## 4. 読み込みと実行フロー

MDSLの読み込みと実行フローは次のように機能します：

1. `Loader`クラスがファイルがMDSLを使用しているかを判断（`.mdsl`拡張子または`app "名前" do`パターンの検出によって）
2. MDSLファイルの場合は`eval`で処理され、従来のRubyファイルの場合は`require`が使用される
3. `app`メソッドは`AppState`インスタンスを作成し、DSLブロックを処理
4. `SimplifiedAppDefinition`クラスは`description`、`icon`などの様々な設定メソッドを処理
5. 設定は設定、機能、プロンプトなどに整理される
6. 完成した状態は`convert_to_class`を通じてRubyクラスに変換される
7. 生成されたクラスは`MonadicApp`を継承し、適切なヘルパーモジュールを含む

## 5. 結論

MDSLの実装は、Rubyの言語機能を活用して強力で表現力豊かなドメイン特化言語を作成する方法を示しています。プロバイダーの違いを抽象化し、クリーンで宣言的な構文を提供することで、開発者は実装の詳細に悩まされることなく、AIアプリケーションの作成に集中できます。

アプリケーションでのMDSLの使用方法については、[Monadic DSLドキュメント](monadic_dsl.md)を参照してください。
