# セッションコンテキスト

セッションコンテキストは、応答のたびに会話から大事な情報を取り出し、サイドバーに表示します。`monadic true` のアプリで動きます。

> **注意**：`monadic true` では、モデルがツールを呼んで文脈を保つ [Session State](monadic-mode.md) も有効になります。2 つはいっしょに使えます。

## 概要

有効にすると、セッションコンテキストは次のことをします。

1. **大事な情報を取り出す**：応答のたびに、抽出のエージェントがそのターンを読み、アプリのスキーマにしたがって情報を取り出します
2. **サイドバーに表示する**：取り出した項目は、サイドバーのパネルに、種類ごとに表示されます
3. **ターンを記録する**：項目ごとに、出てきたターンが記録されます
4. **言い方の違いをまとめる**：敬称の有無だけが違う同じ名前（たとえば「田中」と「田中さん」）は、長いほうの形で 1 つにまとめます

## 仕組み

### アーキテクチャ

1. 利用者がメッセージを送り、モデルが応答します。
2. 抽出のエージェントが、会話と同じプロバイダーに、そのプロバイダーの既定のモデルでターンを送ります。
3. 取り出した項目がブラウザーに送られ、サイドバーのパネルが更新されます。

既定のモデルは、`~/monadic/config/env` の `<PROVIDER>_DEFAULT_MODEL`、なければ Monadic Chat のプロバイダーの既定値です。Ollama では、既定が設定されていなければ、インストールされている最初のモデルを使います。

### デフォルトスキーマ

`context_schema` がないときは、3 つの種類を記録します。

| フィールド | アイコン | 説明 |
|------------|----------|------|
| **Topics** | `fa-tags` | 会話で取り上げた話題 |
| **People** | `fa-users` | 出てきた人の名前 |
| **Notes** | `fa-sticky-note` | 覚えておく大事な事実 |

## 設定

### セッションコンテキストの有効化

`features` に `monadic true` があるアプリで、セッションコンテキストが働きます。

```ruby
app "MyAppOpenAI" do
  features do
    monadic true  # Enables Session Context
  end
end
```

### カスタムコンテキストスキーマ

`context_schema` のブロックで、記録する種類を定義します。

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

`context_schema` のフィールドには、次の項目を指定できます。

| 項目 | 型 | 説明 |
|------|----|------|
| `icon` | String | Font Awesome のアイコンのクラス（例：`"fa-tags"`） |
| `label` | String | サイドバーのパネルに表示する名前 |
| `description` | String | 何を取り出すかを抽出のエージェントに伝えます |

### デフォルトのアイコンとラベル

項目を省いたとき：

- **アイコン**：よくあるフィールドの名前なら名前から選ばれ、それ以外は汎用の丸のアイコンになります
- **ラベル**：フィールドの名前の `_` を空白にし、最初の文字を大文字にしたもの（`:grammar_points` → "Grammar points"）
- **説明**：よくあるフィールドの名前には、既定の説明が使われます

## サイドバー表示

### コンテキストパネル

取り出した文脈は、サイドバーの折りたためるパネルに表示されます。

- **節の見出し**：種類ごとに、アイコン、ラベル、項目の数が表示されます
- **ターンのラベル**：項目はターン（T1、T2 など）ごとにまとめられます。ターンのラベルをクリックすると、そのメッセージまでスクロールします
- **折りたためる節**：節の見出しをクリックすると、開いたり閉じたりします
- **すべて切り替え**：ボタンで、すべての節をまとめて開いたり閉じたりできます
- **ターンの凡例**：ターンの数が表示されます

### 視覚的インジケーター

- 抽出の間は、そのことを示す表示が出ます
- 同じターンの項目はまとめて表示され、新しいターンが先に来ます
- バッジに、種類ごとの項目の数が表示されます
- メッセージを編集すると、そのターンがもう一度取り出され、編集の印が付きます。メッセージを削除すると、そのターンの項目が消え、後のターンの番号が付け直されます

## セッションコンテキストを使用する組み込みアプリ

| アプリ | フィールド |
|--------|------------|
| **Chat Plus** | Topics、People、Notes |
| **Research Assistant** | Topics、Findings、Sources（DeepSeek 版を除く） |
| **Math Tutor** | Concepts、Formulas、Tips |
| **Novel Writer** | Characters、Plot、Settings |
| **Voice Interpreter** | Languages、Phrases、Notes |
| **Language Practice Plus** | Vocabulary、Grammar、Tips |
| **Translate** | Languages、Vocabulary、Notes |
| **Jupyter Notebook** | Topics、Code、Notes |
| **Image Generator** | Styles、Prompts、Notes |
| **Video Generator** | Styles、Prompts、Notes |

## プロバイダーサポート

セッションコンテキストは、すべてのプロバイダーで動きます：OpenAI、Anthropic（Claude）、Google（Gemini）、xAI（Grok）、Mistral、Cohere、DeepSeek、Ollama。`monadic true` を使う Ollama の組み込みのアプリはないので、Ollama での抽出は独自のアプリで使われます。

## 言語サポート

- 項目は会話の言語で取り出されます
- 言語を自動で判別することもできます（`auto`）
- よくある日本語の敬称（さん、くん、ちゃん、様、氏）の有無だけが違う名前は、1 つの項目として扱います

## Privacy Filter

Privacy Filter がオンのときは、抽出のエージェントは伏せた後のテキストを受け取るので、サイドバーには伏せた語の代わりに `<<PERSON_1>>` のような置き換えが表示されます。伏せる処理に失敗したときや、印を付けた語が抽出のエージェントへのリクエストに残るときは、そのターンの抽出は行われません。

## ベストプラクティス

### カスタムスキーマの設計

1. **フィールドを絞る**：フィールドごとに、別の種類の情報にします
2. **説明をはっきり書く**：抽出のエージェントは、説明で何を取り出すかを決めます
3. **意味のあるアイコンを選ぶ**：アイコンがあると、利用者が種類を見つけやすくなります
4. **フィールドの数を抑える**：3〜6 個が読みやすい数です

### スキーマ設計例

**コードレビューのアプリの場合：**
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

- 抽出は、応答を遅らせずに、応答の後に行われます
- ふつう 1〜3 秒かかります（プロバイダーによります）

### データストレージ

- 文脈はサーバーのセッションに保存されます
- セッションの間保たれ、アプリを切り替えたときや新しい会話を始めたときに消えます
- 会話を書き出すと含まれ、読み込むと元に戻ります

### WebSocket通信

文脈の更新は、`context_update` という種類の WebSocket のメッセージでブラウザーに送られます。

```json
{
  "type": "context_update",
  "context": {
    "topics": [
      { "text": "Machine Learning", "turn": 1 },
      { "text": "Neural Networks", "turn": 2 }
    ],
    "people": [],
    "notes": [
      { "text": "User prefers Python", "turn": 1 }
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

1. **`monadic true` を確かめる**：アプリの `features` にあるか確かめます
2. **API キーを確かめる**：抽出のエージェントは、同じプロバイダーの API を使います
3. **Ollama を確かめる**：Ollama では、Ollama が動いていて、モデルが 1 つ以上インストールされているか確かめます
4. **ログを出す**：`~/monadic/config/env` に `EXTRA_LOGGING=true` を設定すると、抽出のログが見られます

### 空のフィールド

- 抽出のエージェントは、ターンごとに新しい情報だけを加えます
- 関係する内容のないフィールドは空のままです
- `description` が、何を取り出すかを表しているか確かめます

### 重複アイテム

- よくある言い方の違いはまとめられます
- 重複が出るときは、説明をもっと具体的にします

## 関連項目

- [Session State（Monadic モード）](monadic-mode.md) - ツールの呼び出しで保つ文脈
- [Monadic DSL](./monadic_dsl.md) - `context_schema` を含む MDSL の文法の全体
