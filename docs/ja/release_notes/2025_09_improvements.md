# 2025年9月改善

## OpenAI CodeとGrok-Codeエージェント統合

### 概要
複雑なコード生成のためのエージェントアーキテクチャパターンを実装。メインの会話モデルが専用モデルに特化したコード生成タスクを委任します。

### 変更点

#### 1. OpenAI Codeアクセスの簡素化
- **以前**: 複雑なモデルリストチェック
- **現在**: シンプルなAPIキー存在チェック
- **理由**: すべてのOpenAI APIキー保持者がOpenAI Codeにアクセス可能

#### 2. Grok-Code-Fast-1エージェント実装
- `Monadic::Agents::GrokCodeAgent`モジュールを作成
- OpenAI Code実装と並行
- すべてのGrokコーディングアプリに統合：
  - Code Interpreter Grok
  - Coding Assistant Grok
  - Jupyter Notebook Grok
  - Research Assistant Grok

#### 3. モデル設定の修正
- Grokアプリをメインモデルとして`grok-code-fast-1`を使用から`grok-4-fast-reasoning`に変更
- Grok-Code-Fast-1はエージェント経由のコード生成にのみ適切に使用されるように
- grok-code-fast-1でツールを使用する際の400エラーを修正

## Jupyter Notebook改善

### 日本語フォントサポート
- matplotlibの日本語フォント自動設定
- ノートブック作成時にフォント設定セルを挿入
- 「Glyph missing from font」警告を抑制
- Noto Sans CJK JPフォントを使用

### ファイル名処理
- `.ipynb`拡張子が常に追加される問題を修正
- 両方の形式を正しく処理：
  - `notebook_20250925_051036.ipynb`（拡張子あり）
  - `notebook_20250925_051036`（拡張子なし）
- すべてのJupyter Notebookバリアント（OpenAI、Claude、Gemini、Grok）に適用

## Coding Assistantファイル操作

### 汎用ファイル操作サポート
すべてのCoding Assistantバリアントにファイル操作を追加：
- `read_file_from_shared_folder` - 共有フォルダからファイルを読み取り
- `write_file_to_shared_folder` - 共有フォルダにファイルを書き込み/追記
- `list_files_in_shared_folder` - ディレクトリ内容をリスト

### サポートされているプロバイダー
- ✅ OpenAI（+ OpenAI Codeエージェント）
- ✅ Claude
- ✅ Gemini
- ✅ Grok（+ Grok-Codeエージェント）
- ✅ Cohere
- ✅ Mistral
- ✅ DeepSeek
- ✅ Perplexity

## 設定とドキュメント

### 設定優先順位のドキュメント化
`docs/reference/configuration.md`に追加：
1. 環境変数（最高優先度）
2. `system_defaults.json`
3. ハードコードされたデフォルト（最低優先度）

### 開発ガイドライン
`CLAUDE.md`を以下で更新：
- コード品質ガイドライン
- 言語使用ルール（日本語コメントと英語識別子）
- OpenAI Codeアクセスに関する注意事項
- 設定優先順位のドキュメント

### 新しいドキュメント
- エージェントアーキテクチャパターンに関する内部開発者ドキュメント
- `docs/release_notes/2025_09_improvements.md` - このファイル

## テスト

### 新しいテストカバレッジ
- `spec/unit/adapters/jupyter_helper_spec.rb` - Jupyterファイル処理テスト
- `spec/unit/apps/coding_assistant_tools_spec.rb` - Coding Assistantファイル操作
- 既存: `spec/unit/agents/openai_code_agent_spec.rb`
- 既存: `spec/unit/agents/grok_code_agent_spec.rb`

### テスト重点領域
- ファイル拡張子処理
- 日本語フォント設定
- エージェントアクセスチェック
- ファイルパス検証
- エラーハンドリング

## 破壊的変更
なし - すべての変更は後方互換性があります

## 移行に関する注意事項
移行は不要です。すべての改善は更新後に自動的に利用可能になります。
