# Gemini ツール継続修正と既知の制限

## 問題
Gemini Jupyter NotebookアプリがツールResultを処理した後、関数呼び出しを続けることができない問題が発生していました。エラーログは次のように表示されました：

```json
"tool_config": {
  "function_calling_config": {
    "mode": "NONE"
  }
}
```

これにより、Geminiがマルチターン会話で後続の関数呼び出しを行うことができず、次のようなエラーが発生しました：
- `exec: "node": executable file not found in $PATH: unknown`

## 根本原因
`/lib/monadic/adapters/vendors/gemini_helper.rb`で、ツールResult（role == "tool"）を処理する際、コードが`function_calling_config.mode`を"NONE"に設定しており、これによりさらなる関数呼び出しが無効になっていました。

## 解決策
Geminiヘルパーを次のように変更：
1. ツールが利用可能な場合は`function_calling_config.mode`を"ANY"に保つ
2. ツールResultを処理した後にツール設定を再追加
3. ツールが設定されていない場合のみモードを"NONE"に設定

### コード変更
**ファイル**：`/lib/monadic/adapters/vendors/gemini_helper.rb`（654-692行目）

**変更前**：
```ruby
if role == "tool"
  # ... ツールResultを処理 ...
  body["tool_config"] = {
    "function_calling_config" => {
      "mode" => "NONE"  # これによりさらなる関数呼び出しが無効化
    }
  }
end
```

**変更後**：
```ruby
if role == "tool"
  # ... ツールResultを処理 ...

  # 継続的な関数呼び出しのためにツールを利用可能に保つ
  if app_tools && !app_tools.empty?
    body["tool_config"] = {
      "function_calling_config" => {
        "mode" => "ANY"  # 関数呼び出しを有効に保つ
      }
    }
    # 継続的な関数呼び出しのためにツールを再追加
    if app_tools.is_a?(Hash) && app_tools["function_declarations"]
      body["tools"] = [{"function_declarations" => app_tools["function_declarations"]}]
    elsif app_tools.is_a?(Array)
      body["tools"] = [{"function_declarations" => app_tools}]
    else
      body["tools"] = [app_tools]
    end
  else
    # ツールが設定されていない場合のみNONEに設定
    body["tool_config"] = {
      "function_calling_config" => {
        "mode" => "NONE"
      }
    }
  end
end
```

## 影響
この修正により次のことが可能になります：
1. **継続的な関数呼び出し**：Geminiが単一の会話で複数の関数呼び出しを行えるようになりました
2. **より良いユーザーエクスペリエンス**：操作のシーケンスを実行する際のエラーがなくなりました
3. **完全なJupyter Notebookサポート**：ユーザーがノートブックを作成し、セルを追加し、自然な流れでコードを実行できます

## テスト
次のことを確認するために統合テストを追加：
- ツールResultを処理した後もツールが利用可能であること
- マルチターン会話で関数呼び出しが引き続き機能すること
- すべての16 Jupyter Notebook Geminiテストが合格すること

## 既知の制限と重要な発見

### Gemini 2.5モデル - 関数呼び出しと構造化出力のトレードオフ
**発見**：Gemini 2.5モデルは、関数呼び出しと構造化JSON出力の間に基本的なトレードオフがあります。両方を同時に持つことはできません。

#### 関数呼び出しの場合
**要件**：MDSL設定で`reasoning_effort: minimal`を使用する必要があります
```ruby
llm do
  provider "gemini"
  model ["gemini-2.5-flash", "gemini-2.0-flash"]
  reasoning_effort "minimal"  # 関数呼び出しに必要
end
```

**`reasoning_effort: minimal`なしの場合**：
- モデルが実際の関数呼び出しではなく疑似コードを生成
- API呼び出しではなく`<execute_ipython>`タグを出力
- 関数宣言が無視される

#### 構造化JSON出力（Monadicモード）の場合
**要件**：`reasoning_effort`パラメータを含めてはいけません
```ruby
llm do
  provider "gemini"
  model ["gemini-2.5-flash", "gemini-2.0-flash"]
  # reasoning_effortパラメータなし
end
```

**monadicモードで`reasoning_effort`を使用した場合**：
- JSONがMarkdownコードブロック（```json）でラップされる
- UIでのJSONパースが壊れる
- コンテキスト情報がアクセス不可能になる

#### アプリタイプ別の解決策戦略

**頻繁な関数呼び出しを持つアプリ**：
- Jupyter Notebook：`reasoning_effort: minimal`を使用
- Code Interpreter：`reasoning_effort: minimal`を使用
- Research Assistant：`reasoning_effort: minimal`を使用

**構造化JSON（Monadicモード）を持つアプリ**：
- Chat Plus：`reasoning_effort`パラメータを削除
- Language Practice Plus：`reasoning_effort`パラメータを削除
- Novel Writer：`reasoning_effort`パラメータを削除

**Monadicアプリの追加要件**：
システムプロンプトに明示的な指示を追加：
```
要件：
- レスポンスは有効なJSONでなければなりません - JSONオブジェクトの前後にテキストはありません
- JSONをMarkdownコードブロックでラップしないでください（```jsonまたは```なし）
- 直接{で開始し、}で終了します
```

### ツール管理の最適化
**実装**：ツール呼び出し制限を使い果たさないように、情報収集ツールとアクションツールを分離

**情報ツール**（呼び出し制限なし）：
- `get_jupyter_cells_with_results`
- `list_jupyter_notebooks`

**アクションツール**（5回の呼び出しに制限）：
- `create_jupyter_notebook`
- `run_jupyter`
- `add_jupyter_cells`
- その他の変更操作

この分離により、実際の変更のためにアクションツールクォータを保持しながら、無制限の読み取り操作が可能になります。

### Gemini 2.5 Flashへの移行
**推奨事項**：`gemini-2.5-flash`を`gemini-2.0-flash`フォールバックと共にプライマリモデルとして使用
- Proモデルよりも優れたコスト/パフォーマンス比
- より速いレスポンス時間
- ほとんどのユースケースに十分な品質

**設定**：
```ruby
model ["gemini-2.5-flash", "gemini-2.0-flash"]  # フォールバック用の配列形式
```

## 関連ファイル
- `/apps/jupyter_notebook/jupyter_notebook_gemini.mdsl` - Gemini Jupyter Notebookアプリ定義
- `/lib/monadic/dsl.rb` - 配列ベースのツール定義のためのDSLサポート
- `/spec/integration/gemini_tool_continuation_integration_spec.rb` - 修正の統合テスト
- `/spec/integration/jupyter_notebook_gemini_spec.rb` - メイン統合テスト
- `/spec/e2e/jupyter_notebook_gemini_e2e_spec.rb` - エンドツーエンドテスト
