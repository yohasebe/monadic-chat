# AutoForge内部ドキュメント

## 概要

AutoForge（公開名：「Artifact Builder」）は、GPT-5、Claude Opus、またはGrok-4-Fast-Reasoningのオーケストレーションと、プロバイダー固有のコード生成（GPT-5-Codex、Claude Opus、またはGrok-Code-Fast-1）を組み合わせた洗練されたマルチレイヤーアプリケーション生成システムです。

## アーキテクチャ

### レイヤーアーキテクチャ

```
┌──────────────────────────────────────────────┐
│              MDSLフレームワーク              │
│  (auto_forge_openai/claude/grok.mdsl)        │
└──────────────────┬───────────────────────────┘
                   │
┌──────────────────▼───────────────────────────┐
│         オーケストレーションレイヤー         │
│  (GPT-5 / Claude Opus / Grok-4-Fast-         │
│   Reasoning via provider APIs)               │
│   - ユーザーインタラクション                 │
│   - 計画と調整                              │
│   - ツール呼び出し                          │
└──────────────────┬───────────────────────────┘
                   │
┌──────────────────▼───────────────────────────┐
│         ツールメソッドレイヤー               │
│         (auto_forge_tools.rb)                │
│   - generate_application                     │
│   - debug_application                        │
│   - list_projects                            │
│   - validate_specification                   │
└──────────────────┬───────────────────────────┘
                   │
┌──────────────────▼───────────────────────────┐
│        コード生成レイヤー                    │
│  (GPT-5-Codex / Claude Opus /                │
│   Grok-Code-Fast-1 via provider agents)      │
│   - HTML/CSS/JS/CLI生成                      │
│   - プロバイダー固有のエージェント経由       │
└──────────────────────────────────────────────┘
```

### 主要コンポーネント

#### 1. MDSL設定（`auto_forge_openai.mdsl`、`auto_forge_claude.mdsl`、`auto_forge_grok.mdsl`）
- 各プロバイダーのアプリインターフェイスとシステムプロンプトを定義
- 利用可能なモデルを設定：
  - OpenAI：オーケストレーションにgpt-5、コード生成にgpt-5-codexとgpt-4.1をフォールバック
  - Claude：オーケストレーションと生成の両方にclaude-sonnet-4-5-20250929
  - Grok：オーケストレーションにgrok-4-fast-reasoningとgrok-4-fast-non-reasoning、コード生成にgrok-code-fast-1
- `generate_additional_file`を含むツールメソッドを登録
- オーケストレーションにプロバイダーのchat/responses APIを使用

#### 2. ツールメソッド（`auto_forge_tools.rb`）
- 各ツールのコアロジックを実装
- プロバイダー固有のエージェントを含む：
  - OpenAIコード生成用の`GPT5CodexAgent`
  - Claudeコード生成用の`ClaudeOpusAgent`
  - Grokコード生成用の`GrokCodeAgent`
- プロジェクト管理、オプションのCLIアセット生成、ファイルI/Oを処理
- オーケストレーションとコード生成間を調整

#### 3. アプリケーションロジック（`auto_forge.rb`）
- メインアプリケーションクラス
- プロジェクトライフサイクルを管理
- ファイル操作を処理
- 変更のためのコンテキスト永続化

#### 4. HTMLジェネレーター
- **OpenAI**: `agents/html_generator.rb`でGPT5CodexAgentを使用 - GPT-5-Codexとインターフェイス
- **Claude**: `agents/html_generator.rb`でClaudeOpusAgentコールバックを使用 - Claudeモデルとclaude_opus_agentを介してインターフェイス
- **Grok**: `agents/grok_html_generator.rb`でGrokCodeAgentを使用 - Grok-Code-Fast-1とインターフェイス
- 各プロバイダーのコード生成モデルに最適化されたプロンプトを構築
- 新規生成と変更の両方を処理
- HTML出力を抽出して検証

#### 5. ユーティリティ（`auto_forge_utils.rb`）
- プロジェクト名のサニタイズ（Unicode対応）
- ディレクトリ管理
- プロジェクト検索とリスト
- クリーンアップ操作

#### 6. デバッガー（`auto_forge_debugger.rb`）
- Selenium統合
- JavaScriptエラー検出
- パフォーマンスメトリクス収集
- 機能テスト（Webアプリのみ、リトライ+ログフィルタリング付き）

## API使用パターン

### モデル選択ロジック

```ruby
# オーケストレーションはMDSLからのモデルを使用：
# - OpenAIにgpt-5
# - Claudeにclaude-sonnet-4-5-20250929
# - Grokにgrok-4-fast-reasoning
# プロバイダーヘルパーは自動的に正しいAPIにルーティング。

# コード生成はプロバイダー固有のエージェントに委譲
call_gpt5_codex(prompt: prompt, app_name: 'AutoForge')          # OpenAI
claude_opus_agent(prompt, 'AutoForgeClaude')                    # Claude
call_grok_code(prompt: prompt, app_name: 'AutoForgeGrok')       # Grok
```

### Responses API vs Chat API

1. **オーケストレーション（MDSL）**：
   - アプリごとに指定されたモデルを使用（`auto_forge_openai` vs `auto_forge_claude`）
   - プロバイダーヘルパー（OpenAIHelper / ClaudeHelper）がAPIルーティングを処理
   - ツール呼び出しと構造化レスポンスを管理

2. **コード生成（プロバイダーエージェント）**：
   - OpenAI用に`GPT5CodexAgent`経由でGPT-5-Codex
   - Claude用に`ClaudeOpusAgent`経由でClaude Opus
   - Grok用に`GrokCodeAgent`経由でGrok-Code-Fast-1
   - すべて決定論的パラメータでプロバイダーのResponses APIを使用
   - プロバイダー固有のプロンプトビルダーが各モデルの強みに最適化
   - 出力サニタイザーがプロバイダー全体で一貫したアーティファクトを保証

## ファイル管理

### ディレクトリ構造
```
~/monadic/data/auto_forge/
├── [AppName]_[YYYYMMDD]_[HHMMSS]/
│   ├── index.html
│   └── context.json（変更用）
```

### Unicode処理
- プロジェクト名の完全なUTF-8サポート
- ファイルシステムで安全でない文字のみ置換
- 日本語/中国語/絵文字文字は保持
- 例：「病気診断アプリ」→「病気診断アプリ_20240127_162936」

### コンテキスト永続化
```json
{
  "original_spec": {
    "name": "TodoApp",
    "type": "productivity",
    "description": "...",
    "features": [...]
  },
  "created_at": "2024-01-27T16:29:36Z",
  "modified_at": "2024-01-27T17:15:22Z",
  "modification_count": 3
}
```

## プロバイダーバリアントと進捗ブロードキャスト

- 3つのMDSLアプリが共有ツールレイヤーをラップ：
  - `auto_forge_openai`：GPT-5オーケストレーション + GPT-5-Codex生成
  - `auto_forge_claude`：Claude Opus 4.1オーケストレーション + 生成
  - `auto_forge_grok`：Grok-4-Fast-Reasoningオーケストレーション + Grok-Code-Fast-1生成
- プロバイダーエージェントは`source`識別子付きの`wait`フラグメントを発行し、WebSocketレイヤーが一時カードに更新をストリーミングできるようにします：
  - OpenAI用の`GPT5CodexAgent`
  - Claude用の`ClaudeOpusAgent`
  - Grok用の`GrokCodeAgent`
- 進捗フラグメントはオプションで`minutes`/`remaining`値を含みます。欠落している場合でも、UIはプロバイダー固有のステータステキストを表示します。
- Web UI翻訳キー（`claudeOpusGenerating`、`grokCodeGenerating`など）がすべてのロケールに追加され、進捗メッセージのローカライズが維持されます。

### Grok固有の実装詳細

- **オーケストレーションモデル**：バランスの取れた品質と速度のために`reasoning_effort: "medium"`付きのGrok-4-Fast-Reasoning
- **コード生成モデル**：Grok-Code-Fast-1（`GrokCodeAgent`のデフォルト）
- **プロンプト最適化**：プロンプトはGrok-Code-Fast-1の強みに合わせて「より小さな集中したタスク」と「反復開発」を強調
- **パフォーマンス**：92トークン/秒のスループット、GPT-5-Codexよりも大幅に高速
- **コスト**：GPT-5-Codexより6-7倍安価
- **強み**：HTML/CSS/JavaScript、SVGグラフィックス、アニメーション、ビジュアルコンポーネント
- **エージェントファイル**：
  - `agents/grok_html_generator.rb`：HTML/CSS/JS生成
  - `agents/grok_cli_generator.rb`：CLIツール生成
  - `lib/monadic/agents/grok_code_agent.rb`の`GrokCodeAgent` mixinを使用

### CLIオプションファイル提案

- `suggest_cli_additional_files`は生成されたスクリプトを検査して、どのオプションファイルを提供するかを決定：
  - READMEは、READMEが存在しない場合にのみ提案されます。
  - 設定テンプレートは、スクリプトが設定パーサー（`configparser`、YAML、`--config`など）を参照する場合にトリガーされます。
  - 依存関係マニフェストは、インポートが`standard_libraries`で定義された言語ごとの標準ライブラリセットを超える場合に提供されます。
  - 使用例（USAGE.md）は、引数解析ライブラリ（argparse、OptionParser、clickなど）が検出された場合に提案されます。
  - 「カスタムアセット」エントリは、任意のファイルをオンデマンドで生成できることをオーケストレーターに思い出させるために常に含まれています。
- `generate_additional_file`は、ディスクに書き込む前にプロジェクトコンテキスト（プロジェクトパス、タイプ、メインファイル）を再検証します。
- カスタムファイルリクエストには、`file_name`（トラバーサルを避けるためにサニタイズ）と`instructions`の両方が必要です。コンテンツは、メインスクリプトの抜粋と既存ファイルを含むリッチプロンプトを使用して、プロバイダーエージェント（`codex_callback`、`call_gpt5_codex`、または`claude_opus_agent`）を通じて生成されます。

## エラーハンドリング

### 一般的なエラーパターン

1. **モデルエラー**：
   - GPT-5-Codexがチャットレスポンスを返す → 適切なプロンプトフォーマットで修正
   - Temperatureパラメータエラー → Responses APIモデルでは削除
   - モデルが見つからない → APIキーがアクセス権を持つことを確認

2. **生成エラー**：
   - プレースホルダーHTML（173バイト） → モックジェネレーターの競合（解決済み）
   - 空のレスポンス → タイムアウトまたはAPI問題
   - 長い生成時間 → GPT-5-Codex / Claude Opusでは正常（2-5分）

3. **ファイルシステムエラー**：
   - Unicodeプロジェクト名 → 適切なエンコーディングで修正
   - ディレクトリ作成失敗 → 権限を確認
   - ファイルが見つからない → list_projectsでプロジェクトが存在することを確認

## デバッグ機能

### Selenium統合

```python
# デバッグスクリプトワークフロー
1. ヘッドレスChromeでHTMLをロード
2. ブラウザコンソールログを収集
3. JavaScriptテストを実行
4. パフォーマンスメトリクスを測定
5. 構造化レポートを返す
```

### デバッグレポート構造
```ruby
{
  success: true/false,
  summary: [...],
  javascript_errors: [...],
  warnings: [...],
  tests: [...],
  performance: {
    loadTime: ms,
    domReadyTime: ms,
    renderTime: ms
  },
  viewport: {width: px, height: px}
}
```

## パフォーマンスに関する考慮事項

### 生成タイミング
- シンプルなアプリ：30-60秒
- 中程度の複雑さ：1-3分
- 複雑なアプリ：2-5分
- 変更：通常、初期生成より高速

### 最適化戦略
1. 変更には既存のコンテンツを再利用
2. プロジェクト検索をキャッシュ
3. 可能な場合は並列ツール実行
4. プロバイダー全体で生成時間を短縮するためにプロンプトを簡潔に保つ

## テスト

### ユニットテスト
```ruby
# spec/unit/apps/auto_forge_orchestrator_spec.rb
- プロジェクトオーケストレーションロジック
- コンテキスト管理

# spec/unit/apps/auto_forge_html_generator_spec.rb
- HTML生成と検証

# spec/unit/apps/auto_forge_codex_response_analyzer_spec.rb
- Codexレスポンスのパースと分析

# spec/unit/apps/auto_forge_error_explainer_spec.rb
- エラーメッセージ生成

# spec/unit/apps/auto_forge_cli_additional_files_spec.rb
- CLIオプションファイル提案ヒューリスティック

# spec/unit/apps/auto_forge_tools_diagnosis_spec.rb
- ツール診断機能
```

### 統合テスト
エンドツーエンドワークフローについてはシステムテストを参照

## 既知の制限

1. **API制約**：
   - GPT-5-CodexはResponses APIが必要
   - 複雑な生成のストリーミングなし
   - レート制限が適用される

2. **ファイル制約**：
   - 単一HTMLファイル出力
   - 外部依存関係なし
   - クライアント側のみ

3. **Selenium制約**：
   - Dockerコンテナが必要
   - file://プロトコルの制限
   - ヘッドレスChromeの制限

## 将来の機能強化

1. **マルチファイルサポート**：個別のファイルを持つ完全なWebアプリケーションを生成
2. **フレームワークサポート**：React、Vue、またはその他のフレームワークを許可
3. **サーバー側コード**：Node.js/Pythonバックエンドを生成
4. **バージョン管理**：プロジェクト用の組み込みgit統合
5. **デプロイメント**：クラウドプラットフォームへの直接デプロイ
6. **共同編集**：マルチユーザープロジェクト変更

## メンテナンスノート

### モデル更新時
1. API型設定について`model_spec.js`を確認
2. Responses API互換性を検証
3. オーケストレーションとコード生成の両方をテスト
4. ドキュメントを更新

### 機能追加時
1. MDSLツール定義を更新
2. `auto_forge_tools.rb`で実装
3. テストを追加
4. 公開と内部の両方のドキュメントを更新

### 一般的な問題と解決策

| 問題 | 原因 | 解決策 |
|-------|-------|----------|
| "Model not found" | モデル名が間違っているかアクセスがない | APIキーの権限を確認 |
| 生成が遅い | GPT-5-Codexでは正常 | 進捗インジケーターを追加 |
| 空のHTML | APIタイムアウト | タイムアウト設定を増やす |
| Unicodeエラー | エンコーディングの問題 | 全体でUTF-8を確保 |
| Selenium失敗 | コンテナが実行されていない | Dockerステータスを確認 |

## セキュリティに関する考慮事項

1. **APIキー**：生成されたコードにログ出力や公開しない
2. **ファイルアクセス**：auto_forgeディレクトリに制限
3. **コード実行**：Seleniumはサンドボックス化されたコンテナで実行
4. **ユーザー入力**：ファイルシステム操作用にサニタイズ
5. **生成されたコード**：サーバー側実行機能なし
