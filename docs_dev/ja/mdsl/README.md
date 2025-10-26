# MDSLドキュメント

このセクションには、Monadic Chatアプリケーションを定義するために使用されるドメイン固有言語であるMonadic DSL（MDSL）の内部ドキュメントが含まれています。

## コンテンツ

- [MDSL型リファレンス](mdsl_type_reference.md) - MDSLの完全な型システムリファレンス

## 概要

Monadic DSL（MDSL）は、インテリジェントチャットアプリケーションを定義するための宣言型言語です。以下を提供します：

- **アプリ定義**：プロパティ、設定、メタデータ
- **ツールメソッド**：パラメータのJSON Schemaを持つ関数定義
- **レスポンスハンドリング**：構造化されたレスポンスフォーマット
- **テンプレートシステム**：プロンプトとレスポンスのERBテンプレート
- **型システム**：パラメータと戻り値のリッチ型アノテーション

## クイックサンプル

```ruby
app "Example App" do
  version "1.0.0"
  author "Developer"
  description "An example application"
  icon "🎯"

  initial_prompt "You are a helpful assistant."

  tool "example_tool" do
    description "Example tool description"
    parameter "input", type: "string", description: "User input", required: true

    execute do |input:|
      result = process(input)
      format_tool_response(success: true, output: result)
    end
  end
end
```

## 関連ドキュメント

- `docs/advanced-topics/monadic_dsl.md` - アプリ開発者向けの公開MDSLリファレンス
- `lib/monadic/dsl.rb` - MDSL実装ソースコード
- `apps/` - MDSLアプリケーション例

参照：
- [Rubyサービス](../ruby_service/) - バックエンド実装詳細
- [アプリの分離とセッション安全性](../app_isolation_and_session_safety.md) - アプリ開発のベストプラクティス
