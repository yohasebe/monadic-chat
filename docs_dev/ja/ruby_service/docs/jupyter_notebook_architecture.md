# Jupyter Notebook アーキテクチャドキュメント

## 概要

このドキュメントは、Monadic Chatにおける異なるAIプロバイダー間でのJupyter Notebook統合のアーキテクチャと実装パターンを説明します。

## 主要なアーキテクチャ決定：MonadicモードとNon-Monadicモード

### 課題

異なるAIプロバイダーは、会話コンテキストを維持するための異なるアプローチを持っています：
- **Monadicモード**：自然に状態を保持する構造化JSONレスポンス
- **Non-Monadicモード**：本質的にコンテキストを維持しない自然言語レスポンス

### プロバイダー設定

| プロバイダー | Monadicモード | 理由 |
|----------|--------------|--------|
| OpenAI | `true` | JSON構造とツール実行の両方をサポート |
| Claude | `true` | Session Stateでノートブックコンテキストを追跡 |
| Gemini | `true` | Session Stateでノートブックコンテキストを追跡 |
| xAI Grok | `true` | Session Stateでノートブックコンテキストを追跡 |

> **注記（2025-12-31更新）**: すべてのプロバイダーは`monadic_load_state`ツールによる一貫したセッション状態管理のため`monadic true`を使用するようになりました。

## セッションコンテキスト管理

### 現在の実装（2025-12-31更新）

すべてのプロバイダーは自動セッション状態管理のために`monadic true`と`monadic_load_state`ツールを使用するようになりました。

ノートブックコンテキストはJupyterツールによって自動的に保存され、以下を使用して取得できます：
```ruby
monadic_load_state(app: "JupyterNotebook...", key: "context")
# 返す: {jupyter_running: true, notebook_created: true, notebook_filename: "example.ipynb", link: "..."}
```

### 歴史的背景（2025-08-28）

以前、Non-monadicプロバイダーは次のような問題を経験していました：
1. ユーザーがノートブックを作成（例：`math_notebook_20250828_123456`）
2. ユーザーがノートブックにセルを追加するように依頼
3. AIが既存のノートブックに追加する代わりに新しいノートブックを作成
4. 根本原因：セッションコンテキスト追跡の欠如

これは、すべてのプロバイダーを共有`monadic_load_state`ツールとともに`monadic true`を使用するように変換することで解決されました。

## プロバイダー固有の実装

### OpenAI
- **ファイル**：`jupyter_notebook_openai.mdsl`
- **Monadic**：`true`
- **コンテキスト追跡**：JSON構造を介して自動
- **特別な処理**：不要

### Claude
- **ファイル**：`jupyter_notebook_claude.mdsl`
- **Monadic**：`true`
- **コンテキスト追跡**：`monadic_load_state`ツールによる自動追跡
- **特別な処理**：API呼び出しを減らすためのバッチ処理

### Gemini
- **ファイル**：`jupyter_notebook_gemini.mdsl`
- **Monadic**：`true`
- **コンテキスト追跡**：`monadic_load_state`ツールによる自動追跡
- **特別な処理**：
  - ユーザーターン開始時にツール結果をクリア（堅牢性向上）
  - Jupyterセル操作のための早期終了チェック

### xAI Grok
- **ファイル**：`jupyter_notebook_grok.mdsl`
- **Monadic**：`true`
- **コンテキスト追跡**：`monadic_load_state`ツールによる自動追跡
- **特別な処理**：
  - 作成+セル追加を統合した`create_and_populate_jupyter_notebook`を使用
  - ユーザーターン開始時に関数戻り値をクリア（堅牢性向上）

## 共通パターン

### ファイル名処理

すべてのプロバイダーは、タイムスタンプ付きファイル名を正しく処理する必要があります：
```
create_jupyter_notebook("math_notebook")
→ 返す："math_notebook_20250828_123456.ipynb"
→ 後続の操作には："math_notebook_20250828_123456"を使用する必要がある
```

### セル構造

すべてのプロバイダー間で標準のセル形式：
```json
{
  "cell_type": "code" | "markdown",
  "source": "コードまたはMarkdownコンテンツ"
}
```

### エラー処理

#### 自動エラー検証（2025-10-21実装）

**問題**：AIエージェントがセル追加後にエラーを一貫してチェックしていないため、セルが正常に追加されたように見えても実際にはエラーが含まれているという静かな失敗が発生していました。

**解決策**：`add_jupyter_cells`ツールに組み込まれた自動検証。

`add_jupyter_cells(run: true)`が呼び出されたとき：
1. **自動検証**：ツールは実行後に内部的に`get_jupyter_cells_with_results`を呼び出す
2. **エラー検出**：すべてのセルで`has_error: true`をチェック
3. **フォーマットされたレスポンス**：
   - 成功：`✓ All N cells executed successfully without errors.`
   - エラー：`⚠️  ERRORS DETECTED IN NOTEBOOK:` とセルインデックス、エラータイプ、メッセージ
4. **AI認識**：エラー情報が自動的にツールレスポンスに含まれる

**利点**：
- AIが検証を覚えておく必要性を排除
- エラーが常に検出され報告されることを保証
- 明確で一貫したエラー報告形式
- 手動での`get_jupyter_cells_with_results`呼び出しが不要

**実装**：`lib/monadic/adapters/jupyter_helper.rb` 415-446行

#### エラー修正ワークフロー

無限ループを防ぐために最大2回の再試行：
1. **検出**：ツールが自動的にセルインデックスとエラータイプを含むエラーを報告
2. **分析**：AIがツールレスポンスからエラーサマリーを読む
3. **詳細情報**（必要に応じて）：完全なトレースバックのために`get_jupyter_cells_with_results`を呼び出す
4. **修正**：`update_jupyter_cell(filename:, index:, content:)`を使用して問題のあるセルを置き換える
5. **検証**：`run_jupyter_cells`で再実行して修正を確認

## テストの考慮事項

### 主要なテストシナリオ

1. **初期作成**：セル付きでノートブックを作成できる
2. **後続の追加**：既存のノートブックにセルを追加できる
3. **コンテキスト保持**：インポートと変数を記憶する
4. **エラー回復**：セル実行エラーを優雅に処理する

### プロバイダー固有のテスト

**マトリックステスト（全プロバイダー）：**
- `spec/integration/provider_matrix/all_providers_all_apps_spec.rb` - すべてのプロバイダー × アプリ組み合わせのスモークテスト

**個別テスト：**
- `spec/integration/jupyter_notebook_gemini_spec.rb` - Gemini固有のテスト
- `spec/e2e/jupyter_notebook_grok_spec.rb` - Grok固有のテスト
- `spec/integration/jupyter_notebook_operations_spec.rb` - 共有操作テスト
- `spec/unit/adapters/jupyter_helper_spec.rb` - jupyter_helper.rbのユニットテスト

## 学んだ教訓

1. **統一されたモードが優れている**：すべてのプロバイダーを`monadic true`に標準化することでコンテキスト管理が簡素化された
2. **堅牢性機能が重要**：ターン開始時のツール結果クリアと早期終了チェックにより重複処理を防止
3. **共有ツールの活用**：`jupyter_operations`共有ツールにより一貫したインターフェースを提供
4. **テストが重要**：セッションコンテキストの問題はマルチターン会話でのみ現れる

## 最近の改善（2025-12-31）

1. **統一モナディックモード**：すべてのプロバイダーが`monadic true`を使用
2. **堅牢性機能**：GeminiとGrokにツール結果クリアと早期終了チェックを追加
3. **パターンマッチング修正**：Grokのリンク表示問題を解決
