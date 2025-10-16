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

Monadicモードは統一インターフェースを通じてすべてのプロバイダーでサポートされています：

- **OpenAI** - `response_format`によるネイティブサポート（ツール実行との併用可能）
- **Claude** - システムプロンプトによるJSON構造化（ツール多用アプリでは`monadic: false`が必要）
- **Gemini** - `responseMimeType`と`responseSchema`の設定（関数呼び出しとの併用不可）
- **Grok** - JSON形式サポート（ツール実行との併用不可）
- **Mistral** - JSONスキーマを使用した`response_format`
- **Cohere** - 構造化出力サポート（単一ツール呼び出しのみ）
- **DeepSeek/Perplexity** - JSONフォーマットサポート
- **Ollama** - `format: "json"`とシステム指示

!> **重要**: ツール/関数呼び出しを多用するアプリケーション（Jupyter NotebookやCode Interpreterなど）では、一部のプロバイダーで最適な動作のために`monadic: false`が必要な場合があります。

## アーキテクチャ

Monadic機能は複数のモジュールを通じて実装されています：

- `monadic_unit`: メッセージをJSON形式でコンテキストとともにラップ
- `monadic_unwrap`: JSONレスポンスから安全にデータを抽出
- `monadic_map`: オプションの処理でコンテキストを変換
- `monadic_html`: UIでJSONコンテキストを折りたたみ可能なHTMLとしてレンダリング

## 実用的な例

### 1. Jupyter Notebookアプリ

Jupyter NotebookアプリはMonadicモードを使用してPythonノートブックセッションの状態を追跡します（注：OpenAIの実装のみがMonadicモードを使用。Claude、Gemini、Grokは適切なツール実行のために`monadic: false`が必要）：

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
- [基本アプリ](../basic-usage/basic-apps.md) - Monadicモードを使用するアプリの例