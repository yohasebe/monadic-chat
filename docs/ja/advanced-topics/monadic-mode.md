# Monadicモード

MonadicモードはMonadic Chatの特徴的な機能で、AIエージェントとの会話を通じて構造化されたコンテキストを維持・更新できます。これにより、より一貫性のある目的志向の対話が可能になります。

## 概要

Monadicモードでは、AIからの各レスポンスにメッセージと構造化されたコンテキストオブジェクトの両方が含まれます。このコンテキストは会話を通じて保持・更新され、AIが状態を維持し、以前の情報を参照できるようになります。

### 基本構造

```json
{
  "message": "ユーザーへのAIの応答",
  "context": {
    "key1": "value1",
    "key2": "value2",
    // 必要に応じて追加のコンテキストフィールド
  }
}
```

## Monadicモードが使用される場合

Monadicモードは信頼性の高い構造化出力（JSON形式）を必要とするため、現在は主にOpenAIのモデルで使用されています。他のプロバイダーでの実験的な実装はありますが、安定したサポートは現在以下に限定されています：

- **OpenAI** - 信頼性の高い構造化出力による完全サポート

信頼性の高い構造化出力をまだサポートしていないプロバイダー（Claude、Gemini、Mistral、Cohereなど）では、Monadic Chatは「トグルモード」と呼ばれる代替実装を使用して、同様のコンテキスト管理機能を提供しています。

?> **注意**: `monadic`と`toggle`の機能は相互排他的です。適切なモードは選択したプロバイダーに基づいて自動的に選択されます。将来のバージョンでは、プロバイダーの構造化出力機能が向上するにつれて、Monadicモードのサポートが追加のプロバイダーに拡張される可能性があります。

## アーキテクチャ

Monadic機能は複数のモジュールを通じて実装されています：

- **`monadic_unit`**: メッセージをJSON形式でコンテキストとともにラップ
- **`monadic_unwrap`**: JSONレスポンスから安全にデータを抽出
- **`monadic_map`**: オプションの処理でコンテキストを変換
- **`monadic_html`**: UIでJSONコンテキストを折りたたみ可能なHTMLとしてレンダリング

## 実用的な例

### 1. Jupyter Notebookアプリ

Jupyter NotebookアプリはMonadicモードを使用してPythonノートブックセッションの状態を追跡します：

```yaml
# アプリが維持するコンテキスト構造
context:
  link: "http://localhost:8888/notebooks/analysis.ipynb"
  modules: ["numpy", "pandas", "matplotlib"]
  functions: [{"name": "process_data", "args": ["df", "threshold"]}]
  variables: ["df", "results", "config"]
```

これによりAIは以下が可能になります：
- 以前に定義された変数や関数を参照
- インポートされているライブラリを把握
- 前のセルに基づいたコードを提案

### 2. Novel Writerアプリ

Novel Writerアプリは構造化されたコンテキストを通じてストーリーの一貫性を維持します：

```yaml
# 創作のためのコンテキスト
context:
  plot: "ビクトリア朝ロンドンを舞台にした探偵小説"
  target_length: 50000
  current_length: 12500
  language: "日本語"
  summary: "探偵ホームズが最初の手がかりを発見..."
  characters: ["シャーロック・ホームズ", "ワトソン博士", "モリアーティ教授"]
  question: "ホームズは捜査をどのように進めるべきか？"
```

### 3. Language Practice Plusアプリ

言語学習では、コンテキストが学習の進捗を追跡します：

```yaml
# 言語練習のためのコンテキスト
context:
  target_language: "英語"
  advice: 
    - "フォーマルな場面では 'would' を使うことを検討してください"
    - "過去形の動詞が必要です"
```

## Monadicアプリの作成

Monadicモードを使用するアプリを作成するには、MDSLファイルで定義します：

```ruby
app "MyAppOpenAI" do
  description "コンテキストを維持するアプリ"
  icon "fa-brain"
  
  features do
    monadic true  # OpenAIでは自動的に設定されます
    context_size 20
  end
  
  initial_prompt <<~PROMPT
    あなたはコンテキストを維持するAIアシスタントです。
    
    以下のJSON形式でレスポンスを返してください：
    {
      "message": "ここにあなたの応答",
      "context": {
        "state": "現在の状態",
        "data": "蓄積されたデータ"
      }
    }
  PROMPT
end
```

## UI表現

Webインターフェースでは、Monadicコンテキストは以下のように表示されます：
- コンテキスト構造を示す折りたたみ可能なセクション
- 空のオブジェクトは明確に「: empty」と表示
- フィールドラベルは太字で表示
- 欠損値は斜体グレーで「no value」と表示

## ベストプラクティス

1. **コンテキストを集中させる**: 後で参照される情報のみを保存
2. **一貫したキーを使用**: 会話を通じて同じコンテキスト構造を維持
3. **増分的に更新**: 変更される部分のみを修正
4. **エラーを適切に処理**: 使用前に常にコンテキストを検証

## トラブルシューティング

コンテキストが適切に更新されない場合は、初期プロンプトで期待されるJSON形式を指定し、AIレスポンスが有効なJSONを含んでいることを確認してください。また、問題を避けるためにコンテキストオブジェクトは適切なサイズに保ってください。

## 関連項目

- [Monadic DSL](./monadic_dsl.md) - 完全なMDSL構文リファレンス
- [基本アプリ](../basic-apps/) - Monadicモードを使用するアプリの例