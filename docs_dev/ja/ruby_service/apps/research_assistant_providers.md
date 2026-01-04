# Research Assistant: プロバイダー固有の実装

このドキュメントでは、Research Assistantがプロバイダーごとに異なる実装を持つ理由と、各バリアントの背後にある設計決定について説明します。

## 概要

Research Assistantは、Monadic Chatで最も複雑なアプリの1つです。以下を組み合わせています：
- ウェブ検索機能
- セッション状態管理（monadicモード）
- ファイル操作
- コードエージェント統合（一部のプロバイダー）
- 進捗追跡

すべてのプロバイダーがこれらの機能を同等にサポートしているわけではないため、プロバイダー固有の実装につながっています。

## プロバイダー比較マトリックス

| プロバイダー | ウェブ検索 | Monadicモード | コードエージェント | ファイルサイズ |
|----------|------------|--------------|------------|-----------|
| **OpenAI** | ネイティブ（Bing） | ✅ 完全 | GPT-5-Codex | 7.1 KB |
| **Claude** | Tavily | ✅ 完全 | - | 6.7 KB |
| **Gemini** | 内部エージェント | ✅ 完全 | - | 6.0 KB |
| **Grok** | ネイティブ（X/Web） | ✅ 完全 | Grok-Code | 6.6 KB |
| **Cohere** | Tavily | ✅ 完全 | - | 6.0 KB |
| **Mistral** | Tavily | ✅ 完全 | - | 6.2 KB |
| **DeepSeek** | Tavily | ❌ 無効 | - | **1.8 KB** |

## なぜDeepSeekが異なるのか

### 問題：ツールループの問題

DeepSeekモデルは、複雑なツールシーケンスを使用すると無限ループに入る傾向があります：

1. **DSML形式の問題**: DeepSeekは不正なDSML形式でツール呼び出しを出力する
2. **マルチツールの混乱**: 複数のツールを持つ複雑なシステムプロンプトが繰り返しツール呼び出しを引き起こす
3. **セッション状態の競合**: Monadicモードの状態追跡ツールが追加のツール呼び出しをトリガーする

### 解決策：簡素化された実装

```ruby
# research_assistant_deepseek.mdsl
system_prompt <<~TEXT
  あなたはユーザーが情報を見つける手助けをするプロフェッショナルな研究アシスタントです。

  ## 重要：ツール呼び出しルール

  1. **各ツールはユーザーメッセージごとに1回のみ呼び出す**
  2. **ツール結果を受け取ったら、すぐに最終回答を提供する**
  3. **結果を受け取った後、同じツールを再度呼び出さない**
  4. **ループでツールを呼び出さない**
TEXT

features do
  # 注意：ツールループ問題のためDeepSeekではmonadicモードを無効化
  monadic false
end
```

**主な違い**:
- **Monadicモードなし**: `save_research_progress`、`load_research_progress`ツールを削除
- **明示的なアンチループ指示**: 繰り返しツール呼び出しを防ぐ明確なルール
- **シンプルなシステムプロンプト**: 約200行から約30行に削減
- **Tavilyのみ**: 複雑なエージェントパターンの代わりに外部検索APIを使用

## プロバイダー固有のウェブ検索実装

### ネイティブ検索プロバイダー

**OpenAI**:
```ruby
# websearch_agentを介したネイティブBing統合を使用
tools do
  import_shared_tools :web_search_tools, visibility: "conditional"
  # websearch_agentはwebsearch: trueのとき自動的に利用可能
end
```

**Grok (xAI)**:
```ruby
# ネイティブX/Twitterおよびウェブ検索を使用
features do
  websearch true  # Grok Live Searchを有効化
end
```

### Tavily検索プロバイダー

**Claude、Cohere、Mistral、DeepSeek**:
```ruby
# ウェブ検索用の外部Tavily API
tools do
  import_shared_tools :web_search_tools, visibility: "conditional"
  # TAVILY_API_KEYが設定されているときtavily_searchが使用される
end
```

### Gemini特殊ケース

**問題**: Gemini 3 APIは、Google SearchグラウンディングとI他のツールを組み合わせる際に制限があります。

**解決策**: ファイル操作と競合しない内部ウェブ検索エージェント：
```ruby
# research_assistant_gemini.mdsl
define_tool "gemini_web_search", "Geminiの内部検索エージェントを使用してウェブを検索" do
  parameter :query, "string", "検索クエリ", required: true
  visibility "conditional"
end
```

**注意**: これは`docs/basic-usage/basic-apps.md`に文書化されています：
> Gemini Research AssistantはネイティブGoogle Searchグラウンディングの代わりに内部ウェブ検索エージェント（`gemini_web_search`）を使用します。

## プロバイダー別セッション状態ツール

### フルセッション状態（ほとんどのプロバイダー）

```ruby
# セッション状態管理用の利用可能なツール
define_tool "load_research_progress", "現在の研究進捗を読み込む"
define_tool "save_research_progress", "レスポンスと研究進捗を保存"
define_tool "add_finding", "ソース付きの重要な発見を追加"
define_tool "add_research_topics", "調査したトピックを追加"
define_tool "add_search", "実行した検索を記録"
define_tool "add_sources", "引用と参照を追加"
define_tool "add_research_notes", "研究観察を追加"
```

### セッション状態なし（DeepSeek）

DeepSeekはツールループを防ぐため、すべてのセッション状態ツールを意図的に除外しています。

## コードエージェント統合

### OpenAI: GPT-5-Codex

```ruby
define_tool "openai_code_agent", "コード生成のためGPT-5-Codexを呼び出す" do
  parameter :task, "string", "コードタスクの説明", required: true
  parameter :research_context, "string", "研究結果からのコンテキスト", required: false
  visibility "conditional"
  unlock_when tool_request: "openai_code_agent"
end
```

### Grok: Grok-Code

```ruby
define_tool "grok_code_agent", "コード生成のためGrok-Code-Fast-1を呼び出す" do
  parameter :task, "string", "コードタスクの説明", required: true
  parameter :research_context, "string", "研究結果からのコンテキスト", required: false
  visibility "conditional"
  unlock_when tool_request: "grok_code_agent"
end
```

### その他のプロバイダー

専用のコードエージェントなし - 代わりにCoding Assistantアプリを使用。

## 温度設定

すべてのResearch Assistantバリアントは、一貫した事実に基づく応答のために`temperature: 0.0`を使用：

```ruby
features do
  temperature 0.0  # 研究精度のための決定論的応答
end
```

## プロバイダー固有の問題のトラブルシューティング

### DeepSeek: ツールが実行されない

**症状**: DeepSeekがDSMLを出力するが、ツールが実行されない

**解決策**:
1. 自動リトライメカニズムがほとんどのケースを処理（最大4回リトライ）
2. 持続的な問題には`deepseek-reasoner`モデルを使用
3. ツールの複雑さを減らすためにクエリを簡素化

### Gemini: 検索が機能しない

**症状**: ウェブ検索が結果を返さない

**確認事項**:
1. 内部検索エージェントが使用されていることを確認（Googleグラウンディングではない）
2. クエリが長すぎたり複雑すぎたりしないか確認
3. APIクォータ制限を確認

### OpenAI/Grok: ネイティブ検索の失敗

**症状**: websearch_agentがエラーを返す

**確認事項**:
1. APIキーに検索権限があることを確認
2. レート制限を確認
3. 利用可能な場合はTavilyフォールバックを試す

## 新しいプロバイダーの追加

新しいプロバイダー用のResearch Assistantを追加する際は、以下を考慮：

1. **ウェブ検索機能**:
   - ネイティブ検索が利用可能？それを使用。
   - ネイティブ検索がない？Tavily統合を追加。

2. **ツール呼び出しの信頼性**:
   - 複雑なツールシーケンスをテスト
   - ループが発生する場合、DeepSeekのように簡素化

3. **セッション状態の互換性**:
   - Monadicモードを徹底的にテスト
   - ツール呼び出しと競合する場合は無効化

4. **システムプロンプトの長さ**:
   - 一部のプロバイダーは長いプロンプトをより良く処理
   - モデル機能に基づいて複雑さを調整

## 関連ドキュメント

- [DeepSeek アーキテクチャ](../vendors/deepseek_architecture.md) - DSMLパースと自動リトライ
- [思考/推論表示](../thinking_reasoning_display.md) - 推論コンテンツ処理
- [Monadicアーキテクチャ](../monadic_architecture.md) - セッション状態管理
- [ウェブ検索統合](../../basic-usage/basic-apps.md#research-assistant) - ユーザードキュメント
