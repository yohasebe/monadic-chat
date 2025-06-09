# 開発ワークフロー

このドキュメントには、Monadic Chatプロジェクトに貢献する開発者向けのガイドラインと指示が含まれています。

?> このドキュメントは、Monadic Chat のレシピファイルの開発者ではなく、Monadic Chat自体の開発者向けです。

## テスト

### テストフレームワーク
- **JavaScript**: フロントエンドコードのテストにJestを使用
- **Ruby**: バックエンドコードのテストにRSpecを使用

### テスト構造
- JavaScriptテストは `test/frontend/` に配置
- Rubyテストは `docker/services/ruby/spec/` に配置
- Jestの設定は `jest.config.js` に定義
- JavaScriptのグローバルテスト設定は `test/setup.js` に定義

### テスト実行方法
#### Rubyテスト
```bash
rake spec
```

#### JavaScriptテスト
```bash
rake jstest        # 成功するJavaScriptテストを実行
npm test           # 上記と同じ
rake jstest_all    # すべてのJavaScriptテストを実行
npm run test:watch # ウォッチモードでテストを実行
npm run test:coverage # カバレッジレポート付きでテストを実行
```

#### すべてのテスト
```bash
rake test  # RubyとJavaScriptの両方のテストを実行
```

## MDSL開発ツール

### CLIツール: mdsl_tool_completer

`mdsl_tool_completer`は、MDSL自動補完機能のテストと検証を行うコマンドラインツールです。MDSLアプリケーションのツール自動補完をプレビューし、デバッグするのに役立ちます。

#### 場所
```bash
docker/services/ruby/bin/mdsl_tool_completer
```

#### 使用方法

**基本プレビュー:**
```bash
# 特定のアプリの自動補完をプレビュー
ruby bin/mdsl_tool_completer novel_writer
ruby bin/mdsl_tool_completer drawio_grapher
```

**検証モード:**
```bash
# 定義と実装の間のツール一貫性を検証
ruby bin/mdsl_tool_completer --action validate app_name
ruby bin/mdsl_tool_completer --action validate novel_writer
```

**分析モード:**
```bash
# 詳細出力付きの詳細分析
ruby bin/mdsl_tool_completer --action analyze app_name
ruby bin/mdsl_tool_completer --action analyze --verbose novel_writer
```

**全アプリ分析:**
```bash
# システム内のすべてのアプリを分析
ruby bin/mdsl_tool_completer --action analyze --all
```

#### コマンドオプション

- `--action validate`: ツール実装の一貫性をチェック
- `--action analyze`: 詳細なメソッド分析を実行
- `--verbose`: 分析の詳細出力を有効にする
- `--all`: 利用可能なすべてのアプリを処理
- `--help`: 使用方法の情報を表示

#### 出力例

**プレビューモード:**
```bash
$ ruby bin/mdsl_tool_completer novel_writer

=== MDSL Tool Completer ===
App: novel_writer
Tools file: /path/to/novel_writer_tools.rb

Auto-completed tools:
- count_num_of_words (text: string)
- count_num_of_characters (text: string)
- save_content_to_file (content: string, filename: string)

Total methods found: 3
```

**検証モード:**
```bash
$ ruby bin/mdsl_tool_completer --action validate novel_writer

=== Tool Implementation Validation ===
✓ count_num_of_words: Implementation found
✓ count_num_of_characters: Implementation found  
✓ save_content_to_file: Implementation found

All tools have valid implementations.
```

#### 環境変数

このツールは統一デバッグシステムを使用します：
- `MONADIC_DEBUG=mdsl`: MDSLデバッグ出力を有効化
- `MONADIC_DEBUG_LEVEL=debug`: デバッグの詳細度を設定

レガシー変数（サポートされていますが非推奨）：
- `MDSL_AUTO_COMPLETE=debug`: MDSLデバッグ出力を有効化
- `APP_DEBUG=1`: 一般的なデバッグ出力を有効化

### MDSL開発のベストプラクティス

#### 一般的な開発上の問題

**ツール実装の検証：**
```bash
# ツールが適切に定義されているか確認
ruby bin/mdsl_tool_completer --action validate your_app_name
```

**自動補完のデバッグ：**
```bash
# 自動補完されるツールをプレビュー
ruby bin/mdsl_tool_completer your_app_name

# 自動補完の問題をデバッグ（新しい統一システム）
export MONADIC_DEBUG=mdsl
export MONADIC_DEBUG_LEVEL=debug
ruby bin/mdsl_tool_completer your_app_name

# またはレガシー方式（非推奨）
export MDSL_AUTO_COMPLETE=debug
ruby bin/mdsl_tool_completer your_app_name
```

#### プロバイダー固有の考慮事項

- **関数の制限**: OpenAI/Geminiは最大20個の関数呼び出しをサポート、Claudeは最大16個まで
- **コード実行**: すべてのプロバイダが`run_code`を使用（以前はAnthropicが`run_script`を使用）
- **配列パラメータ**: OpenAIは配列パラメータに`items`プロパティが必要

## MDSL自動補完の制御

MDSL自動補完システムは環境変数で制御できます：

```bash
# 自動補完を無効化（MDSLファイルのデバッグ時に便利）
export MDSL_AUTO_COMPLETE=false

# 詳細なデバッグログ付きで有効化
export MDSL_AUTO_COMPLETE=debug

# 通常通り有効化
export MDSL_AUTO_COMPLETE=true

# デフォルトの動作（自動補完は無効）
# MDSL_AUTO_COMPLETEは未設定またはデフォルトでfalse
```

## 重要：セットアップスクリプトの管理

`docker/services/python/`、`docker/services/ruby/`、`docker/services/ollama/`にある`pysetup.sh`、`rbsetup.sh`、`olsetup.sh`ファイルは、コンテナビルド中、追加パッケージやモデルをインストールするためにユーザーが共有フォルダの`config`ディレクトリに配置したものに置き換えられます。バージョン管理システム（Git）には、常にこれらのスクリプトのオリジナルバージョンをコミットする必要があります。リポジトリに変更をコミットする前に、以下のいずれかの方法でこれらのファイルをリセットします。

#### 方法1：リセットスクリプトの使用

提供されたリセットスクリプトを実行します：

```bash
./docker/services/reset_setup_scripts.sh
```

これにより、セットアップスクリプトのオリジナルバージョンがgitから復元されます。

#### 方法2：手動リセット

あるいは、gitを使用して手動でファイルをリセットすることもできます：

```bash
git checkout -- docker/services/python/pysetup.sh docker/services/ruby/rbsetup.sh docker/services/ollama/olsetup.sh
```

### Gitプリコミットフック（オプション）

各コミット前に自動的にこれらのファイルをリセットするgitプリコミットフックを設定できます：

1. `.git/hooks/`ディレクトリに`pre-commit`という名前のファイルを作成します：

```bash
touch .git/hooks/pre-commit
chmod +x .git/hooks/pre-commit
```

2. プリコミットフックに以下の内容を追加します：

```bash
#!/bin/bash
# .git/hooks/pre-commit - コミット前に自動的にセットアップスクリプトをリセット

# コミット用にステージングされているファイルを取得
STAGED_FILES=$(git diff --cached --name-only)

# セットアップスクリプトが変更されているかチェック
if echo "$STAGED_FILES" | grep -q "docker/services/python/pysetup.sh\|docker/services/ruby/rbsetup.sh"; then
  echo "⚠️ コミット内でセットアップスクリプトの変更が検出されました。"
  echo "⚠️ gitからオリジナルバージョンにリセットしています..."
  
  # リセット
  git checkout -- docker/services/python/pysetup.sh
  git checkout -- docker/services/ruby/rbsetup.sh
  
  # ステージングに再追加
  git add docker/services/python/pysetup.sh
  git add docker/services/ruby/rbsetup.sh
  
  echo "✅ セットアップスクリプトがリセットされました。コミットを続行します。"
fi

# コミットを進める
exit 0
```

このプリコミットフックは、コミット前にセットアップスクリプトへの変更を自動的に検出してリセットします。

## ユーザー向け

コンテナをカスタマイズしたいユーザーは、以下の場所にカスタムスクリプトを配置する必要があります：
- Pythonのカスタマイズには`~/monadic/config/pysetup.sh`
- Rubyのカスタマイズには`~/monadic/config/rbsetup.sh`

これらはローカルでコンテナをビルドする際に自動的に使用されますが、リポジトリファイルには影響しません。

