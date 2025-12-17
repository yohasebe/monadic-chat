# セッションコンテキスト

セッションコンテキストは、Monadicアプリのための自動コンテキスト追跡機能で、会話から重要な情報をリアルタイムで抽出・表示します。この機能は `monadic: true` 設定と連携して、インテリジェントなコンテキスト管理を提供します。

> **注意**: セッションコンテキストは `monadic: true` で有効になる2つのコンテキスト機能のうちの1つです。もう1つは明示的なツールベースのコンテキスト管理である[Session State](monadic-mode.md)です。これらの機能は補完関係にあります。

## 概要

セッションコンテキストが有効な場合、以下を自動的に行います：

1. **重要情報の抽出**：各AIレスポンス後に、軽量な抽出エージェントが会話を分析し、設定可能なスキーマに基づいて関連情報を抽出
2. **サイドバーに表示**：抽出されたコンテキストはサイドバーの専用パネルに、カテゴリ別に整理されて表示
3. **会話ターンの追跡**：各抽出項目にはターン情報が含まれ、いつ言及されたかを表示
4. **インテリジェントな重複排除**：類似のバリエーション（例：「田中」と「田中さん」）を認識し、最も完全な形式のみを保持

## 仕組み

### アーキテクチャ

```
ユーザーメッセージ → AIレスポンス → コンテキスト抽出エージェント → サイドバー更新
                                            ↓
                                     同じプロバイダーAPI
                                     （軽量モデル）
```

コンテキスト抽出エージェントは、メイン会話と同じプロバイダーへの直接HTTP API呼び出しを使用し、コスト効率の良いモデルで構造化情報を抽出します。

### デフォルトスキーマ

カスタム設定なしの場合、セッションコンテキストは3つのカテゴリを追跡します：

| フィールド | アイコン | 説明 |
|-----------|---------|------|
| **Topics** | 🏷️ | 会話で議論された主なトピック |
| **People** | 👥 | 言及された人物の名前 |
| **Notes** | 📝 | 覚えておくべき重要な事実 |

## 設定

### セッションコンテキストの有効化

セッションコンテキストは、featuresで `monadic: true` を設定したアプリで自動的に有効になります：

```ruby
app "MyAppOpenAI" do
  features do
    monadic true  # セッションコンテキストを有効化
  end
end
```

### カスタムコンテキストスキーマ

`context_schema` ブロックを使用して、アプリ固有の情報を追跡するカスタムスキーマを定義できます：

```ruby
app "LanguageTutorOpenAI" do
  features do
    monadic true
  end

  context_schema do
    field :vocabulary, icon: "fa-book", label: "Vocabulary",
          description: "New words and expressions learned"
    field :grammar_points, icon: "fa-list-check", label: "Grammar",
          description: "Grammar concepts covered"
    field :corrections, icon: "fa-pen", label: "Corrections",
          description: "Mistakes and their corrections"
    field :practice_topics, icon: "fa-comments", label: "Practice Topics",
          description: "Conversation topics for practice"
  end
end
```

### フィールドオプション

`context_schema` の各フィールドは以下のオプションを受け付けます：

| オプション | タイプ | 説明 |
|-----------|--------|------|
| `icon` | String | FontAwesomeアイコンクラス（例：`"fa-tags"`） |
| `label` | String | サイドバーパネルに表示される名前 |
| `description` | String | 抽出エージェントが何を抽出すべきか理解するための説明 |

### デフォルトのアイコンとラベル

指定しない場合、フィールドは適切なデフォルト値を使用します：

- **アイコン**：フィールド名から導出、または汎用の丸アイコンにフォールバック
- **ラベル**：フィールド名をタイトルケースに変換（例：`:grammar_points` → "Grammar Points"）

## サイドバー表示

### コンテキストパネル

抽出されたコンテキストはサイドバーの折りたたみ可能なパネルに表示されます：

- **セクションヘッダー**：各カテゴリにアイコン、ラベル、アイテム数バッジを表示
- **ターンラベル**：アイテムは会話ターン（T1、T2など）でグループ化
- **折りたたみ可能なセクション**：セクションヘッダーをクリックして展開/折りたたみ
- **全て切り替え**：全セクションを一度に展開/折りたたむボタン
- **ターン凡例**：会話ターンの総数を表示

### 視覚的インジケーター

- 同じターンのアイテムはまとめて表示
- 新しいアイテム（高いターン番号）がセクション内で最初に表示
- バッジが各カテゴリのアイテム総数を表示

## セッションコンテキストを使用する組み込みアプリ

以下の組み込みアプリがセッションコンテキストを使用しています：

| アプリ | コンテキストフィールド |
|-------|----------------------|
| **Chat Plus** | Topics, People, Notes（デフォルトスキーマ） |
| **Research Assistant** | Topics, People, Notes（デフォルトスキーマ） |
| **Math Tutor** | Topics, People, Notes（デフォルトスキーマ） |
| **Novel Writer** | Topics, People, Notes（デフォルトスキーマ） |
| **Voice Interpreter** | Topics, People, Notes（デフォルトスキーマ） |
| **Language Practice Plus** | Target Language, Language Advice, Summary |

## プロバイダーサポート

セッションコンテキストは全ての主要AIプロバイダーで動作します：

- **OpenAI**
- **Anthropic**（Claude）
- **Google**（Gemini）
- **xAI**（Grok）
- **Mistral**
- **Cohere**（Command）
- **DeepSeek**
- **Ollama**（ローカルモデル）

抽出には各プロバイダーに適した軽量モデルを使用し、コストと遅延を最小限に抑えます。

## 言語サポート

コンテキスト抽出は会話の言語に自動的に合わせます：

- 会話と同じ言語でアイテムを抽出
- 自動言語検出（`auto` モード）をサポート
- 敬称のバリエーション（日本語の「さん」「くん」「様」などの接尾辞）を処理

## ベストプラクティス

### カスタムスキーマの設計

1. **フィールドを明確に**：各フィールドは異なる情報カテゴリを表すべき
2. **明確な説明を記述**：抽出エージェントは説明を使用して何を抽出するか理解
3. **意味のあるアイコンを選択**：アイコンはユーザーがカテゴリを素早く識別するのに役立つ
4. **フィールド数を制限**：使いやすさのためには3〜6フィールドが最適

### スキーマ設計例

**コードレビューアプリの場合：**
```ruby
context_schema do
  field :files_reviewed, icon: "fa-file-code", label: "Files Reviewed",
        description: "Source code files that were reviewed"
  field :issues_found, icon: "fa-bug", label: "Issues Found",
        description: "Bugs, problems, or code smells identified"
  field :suggestions, icon: "fa-lightbulb", label: "Suggestions",
        description: "Improvement suggestions and recommendations"
end
```

**リサーチアシスタントの場合：**
```ruby
context_schema do
  field :topics, icon: "fa-tags", label: "Research Topics",
        description: "Main research subjects and areas explored"
  field :sources, icon: "fa-link", label: "Sources",
        description: "References, papers, and URLs cited"
  field :key_findings, icon: "fa-star", label: "Key Findings",
        description: "Important discoveries and conclusions"
  field :questions, icon: "fa-question", label: "Open Questions",
        description: "Questions that need further investigation"
end
```

## 技術的注意事項

### パフォーマンス

- 抽出は各レスポンス後に非同期で実行
- メッセージフローの再トリガーを避けるため、直接HTTP API呼び出し（WebSocketではなく）を使用
- 典型的な抽出遅延：プロバイダーによって1〜3秒

### データストレージ

- コンテキストはサーバー上のセッション状態に保存
- コンテキストはセッション期間中持続
- アプリを切り替えたり、新しい会話を開始するとコンテキストはクリア

### WebSocket通信

コンテキスト更新は `context_update` メッセージタイプでWebSocket経由で送信されます：

```json
{
  "type": "context_update",
  "context": {
    "topics": [
      { "text": "機械学習", "turn": 1 },
      { "text": "ニューラルネットワーク", "turn": 2 }
    ],
    "people": [],
    "notes": [
      { "text": "ユーザーはPythonを好む", "turn": 1 }
    ]
  },
  "schema": {
    "fields": [
      { "name": "topics", "icon": "fa-tags", "label": "Topics", "description": "..." },
      ...
    ]
  },
  "timestamp": 1699500000.123
}
```

## トラブルシューティング

### コンテキストが表示されない

1. **`monadic: true`を確認**：アプリで機能が有効になっているか確認
2. **APIキーを確認**：抽出エージェントは同じプロバイダーのAPIにアクセスする必要がある
3. **プロバイダーを確認**：一部のローカルモデル（Ollama）は抽出に使用できない場合がある
4. **ログを有効化**：`~/monadic/config/env` で `EXTRA_LOGGING=true` を設定して抽出ログを確認

### 空のフィールド

- 抽出エージェントは各ターンから新しい情報のみを追加
- 関連コンテンツがないフィールドは空のまま
- `description` テキストが抽出を正しくガイドしているか確認

### 重複アイテム

- 重複排除ロジックは一般的なバリエーションを処理
- 重複が表示される場合は、説明をより具体的にすることを検討
- 日本語の敬称バリエーション（さん、くん、など）は自動的に処理

## 関連項目

- [Session State（Monadicモード）](monadic-mode.md) - 明示的なツールベースのコンテキスト管理
- [Monadic DSL](./monadic_dsl.md) - `context_schema`を含む完全なMDSL構文リファレンス
- [基本アプリ](../basic-usage/basic-apps.md) - セッションコンテキストを使用するアプリの例
