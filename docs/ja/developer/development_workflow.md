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
- アプリ固有の診断スクリプトは `docker/services/ruby/scripts/diagnostics/apps/{app_name}/` に配置
- Jestの設定は `jest.config.js` に定義
- JavaScriptのグローバルテスト設定は `test/setup.js` に定義

### アプリ固有の診断スクリプト
特定のテストや診断が必要なアプリケーションの場合：
- 診断スクリプトは診断ディレクトリに配置: `docker/services/ruby/scripts/diagnostics/apps/{app_name}/`
- 説明的な名前を使用: `test_feature_name.sh` または `diagnose_issue.rb`
- アプリ固有の診断スクリプトをプロジェクトルートディレクトリに配置しない
- 例: Concept Visualizerの診断スクリプトは `docker/services/ruby/scripts/diagnostics/apps/concept_visualizer/` に配置

?> **重要**: 診断スクリプトは `apps/{app_name}/test/` ディレクトリに配置してはいけません。アプリ内の `test/` サブディレクトリ内のファイルは、テストスクリプトがアプリケーションとしてロードされるのを防ぐため、アプリロード時に無視されます。

### テスト実行方法

**注意**: `rake server:debug`を使用して開発する場合、RubyテストはローカルのRuby環境を使用してホスト上で直接実行されます。

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

### MDSL自動補完システム（実験的機能）

**⚠️ 注意: これは実験的な機能であり、将来のバージョンで変更または削除される可能性があります。**

MDSL自動補完システムは、Ruby実装とMDSL宣言の間でツール定義を同期させるという開発課題の解決を目指しています。

#### 解決する問題

Monadic Chatアプリでは、以下が必要です：
1. Rubyでツールメソッドを実装（`*_tools.rb`ファイル）
2. LLMが認識できるようにMDSLでツールを宣言（`*.mdsl`ファイル）

自動補完なしでは、すべてのメソッドシグネチャを手動で複製する必要があり、これは：
- 時間がかかり、エラーが発生しやすい
- パラメータ変更時の保守が困難
- 宣言を忘れやすく、ツールがLLMから利用できなくなる

#### 動作の仕組み

有効化すると、システムは自動的に：
1. `*_tools.rb`ファイルのRubyメソッドを**検出**
2. メソッドシグネチャを**分析**し、パラメータタイプを推論
3. 対応するMDSLツール定義を**生成**
4. 欠落している定義でMDSLファイルを**更新**

#### 例

このRubyメソッドを書くと：
```ruby
# novel_writer_tools.rb
def count_num_of_words(text: "")
  text.split.size
end
```

システムが自動的にこのMDSL定義を生成：
```ruby
# novel_writer_openai.mdsl
define_tool "count_num_of_words", "Count the num of words" do
  parameter :text, "string", "The text content to process"
end
```

#### 自動補完の制御

`~/monadic/config/env`ファイルで設定：
```
# 無効化（デフォルト） - ツールは実行時に動作するがMDSLファイルは変更されない
MDSL_AUTO_COMPLETE=false

# 有効化 - 欠落しているツール定義でMDSLファイルを自動更新
MDSL_AUTO_COMPLETE=true

# デバッグモード - 有効化と同じだが詳細ログを出力
MDSL_AUTO_COMPLETE=debug
```

#### 重要な注意事項

- **実験的機能**: この機能はまだ開発中であり、予期しない動作をする可能性があります
- **デフォルトはOFF**: MDSLファイルを変更するには明示的に有効化が必要
- **実行時 vs ビルド時**: 無効でもツールは実行時に利用可能
- **バックアップファイル**: MDSLファイル変更前にバックアップを作成
- **標準ツール**: MonadicAppから継承したツールは自動的に除外
- **スマート検出**: ツールのようなシグネチャを持つパブリックメソッドのみ処理

#### 既知の制限

- 複雑なパラメータタイプを正しく推論できない場合がある
- 手動のカスタマイズを上書きする可能性がある
- 有効時にアプリのロードパフォーマンスに影響を与える
- 本番環境での使用は推奨されない

## デバッグシステム

Monadic Chatは環境変数で制御される統一デバッグシステムを使用します：

### デバッグカテゴリ
- `all`: すべてのデバッグメッセージ
- `app`: 一般的なアプリケーションデバッグ
- `embeddings`: テキスト埋め込み操作
- `mdsl`: MDSLツール補完
- `tts`: テキスト読み上げ操作
- `drawio`: DrawIOグラファー操作
- `ai_user`: AIユーザーエージェント
- `web_search`: Web検索操作（Tavilyを含む）
- `api`: APIリクエストとレスポンス

### デバッグレベル
- `none`: デバッグ出力なし（デフォルト）
- `error`: エラーのみ
- `warning`: エラーと警告
- `info`: 一般情報
- `debug`: 詳細なデバッグ情報
- `verbose`: 生データを含むすべて

### エラー処理の改善
- **エラーパターン検出**: システムは繰り返されるエラーを自動検出し、3回目以降停止
- **UTF-8エンコーディング**: すべてのレスポンスがフォールバックエンコーディング置換で適切に処理
- **無限ループ防止**: 「Maximum function call depth exceeded」エラーを防ぐためツール呼び出しを制限
- **正常な劣化**: APIキーがない場合はクラッシュではなく明確なエラーメッセージを表示

### 使用例
`~/monadic/config/env`ファイルに以下を追加：
```
# Web検索のデバッグ出力を有効化
MONADIC_DEBUG=web_search
MONADIC_DEBUG_LEVEL=debug

# 複数のカテゴリを有効化
MONADIC_DEBUG=api,web_search,mdsl

# すべてのデバッグ出力を有効化
MONADIC_DEBUG=all
MONADIC_DEBUG_LEVEL=verbose

# APIデバッグ（Electronの「Extra Logging」に相当）
MONADIC_DEBUG=api
```

## MDSL開発のベストプラクティス

### ファイル構造
Monadic ChatアプリケーションはMDSL（Monadic Domain Specific Language）形式を使用します：

- **アプリ定義**: `app_name_provider.mdsl` (例: `chat_openai.mdsl`)
- **ツール実装**: `app_name_tools.rb` (例: `chat_tools.rb`)
- **共有定数**: `app_name_constants.rb` (オプション)

### ツール実装パターン

MDSLアプリケーションを開発する際は、カスタムツールにファサードパターンを常に実装してください：

```ruby
# app_name_tools.rb
class AppNameProvider < MonadicApp
  def custom_method(param:, options: {})
    # 1. 入力検証
    raise ArgumentError, "Parameter required" if param.nil?
    
    # 2. 基底の実装を呼び出し
    result = perform_operation(param, options)
    
    # 3. 構造化されたレスポンスを返す
    { success: true, data: result }
  rescue StandardError => e
    { success: false, error: e.message }
  end
end
```

### 空のtoolsブロックの問題

**重要**: MDSLファイル内の空の`tools do`ブロックは「Maximum function call depth exceeded」エラーを引き起こします。常に以下のいずれかを実施してください：

1. **MDSLファイル内でツールを明示的に定義**:
```ruby
tools do
  define_tool "fetch_text_from_pdf", "Extract text from PDF" do
    parameter :pdf, "string", "PDF filename", required: true
  end
end
```

2. **標準ツールを継承するコンパニオンツールファイルを作成**:
```ruby
# app_name_tools.rb
class AppNameProvider < MonadicApp
  # MonadicAppから標準ツールを継承
end
```

### 一般的な開発上の問題

**自動補完のデバッグ：**
1. `~/monadic/config/env`ファイルに以下を追加：
```
# デバッグ出力付きで自動補完を有効化
MDSL_AUTO_COMPLETE=debug
```

2. サーバーを起動してアプリをロード：
```bash
rake server:start
```

3. コンソール出力で自動補完メッセージを確認

**手動ツール検証：**
```bash
# Rubyでツールが正しく実装されているか確認
grep -n "def " apps/your_app/your_app_tools.rb

# MDSLでツール定義を検証
grep -A5 "tools do" apps/your_app/your_app_provider.mdsl
```

### プロバイダー固有の考慮事項

- **関数の制限**: OpenAI/Geminiは最大20個の関数呼び出しをサポート、Claudeは最大16個まで
- **コード実行**: すべてのプロバイダが`run_code`を使用
- **配列パラメータ**: OpenAIは配列パラメータに`items`プロパティが必要

## MDSL自動補完の制御

MDSL自動補完システムは設定変数で制御できます。`~/monadic/config/env`ファイルで設定：

```
# 自動補完を無効化（MDSLファイルのデバッグ時に便利）
MDSL_AUTO_COMPLETE=false

# 詳細なデバッグログ付きで有効化
MDSL_AUTO_COMPLETE=debug

# 通常通り有効化
MDSL_AUTO_COMPLETE=true

# デフォルトの動作（自動補完は無効）
# MDSL_AUTO_COMPLETEは未設定またはデフォルトでfalse
```

## 重要：セットアップスクリプトの管理

リポジトリ内の`pysetup.sh`と`rbsetup.sh`ファイルはプレースホルダースクリプトで、コンテナビルド中に`~/monadic/config/`からユーザー提供のバージョンに置き換えられます。常にオリジナルのプレースホルダーバージョンをGitにコミットしてください。変更をコミットする前に、以下のいずれかの方法でこれらのファイルをリセットします：

注意：`olsetup.sh`スクリプトはOllamaモデルインストール用にユーザーが`~/monadic/config/`に作成するもので、リポジトリにプレースホルダーバージョンはありません。

#### 方法1：リセットスクリプトの使用

提供されたリセットスクリプトを実行します：

```bash
./docker/services/reset_setup_scripts.sh
```

これにより、セットアップスクリプトのオリジナルバージョンがgitから復元されます。

#### 方法2：手動リセット

あるいは、gitを使用して手動でファイルをリセットすることもできます：

```bash
git checkout -- docker/services/python/pysetup.sh docker/services/ruby/rbsetup.sh
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

## 開発環境のセットアップ

### 開発用にMonadic Chatを実行する

開発目的では、ElectronアプリなしでMonadic Chatを実行できます：

```bash
rake server:debug
```

このコマンドは：
- `EXTRA_LOGGING=true`でデバッグモードでサーバーを起動（rake server:debugコマンドにより自動設定）
- Rubyコンテナは起動せず、ホストのRubyランタイムを使用
- 他のすべてのコンテナを起動（Python、PostgreSQL、pgvector、利用可能な場合はOllama）
- ホスト上の`/docker/services/ruby/`のファイルを直接使用
- ブラウザで`http://localhost:4567`からWeb UIにアクセス可能

このセットアップにより以下が可能になります：
- コンテナを再ビルドせずにRubyコードを編集して即座に変更を確認
- ローカルのRuby開発ツール（デバッガ、リンターなど）を使用
- ブラウザインターフェースで変更を素早くテスト
- 必要な他のサービスはコンテナで実行を維持

### コンテナを使用したローカル開発
コンテナ機能を使用しながらローカルで開発する場合：
- **Rubyコンテナ**: ローカルRuby環境を使用するために停止可能
- **その他のコンテナ**: 依存するアプリのために実行を継続する必要がある
- **Pythonコンテナ**: LaTeXを使用するConcept VisualizerやSyntax Treeなどのアプリに必要
- **パス**: `IN_CONTAINER`環境変数により自動調整

### コンテナ依存アプリのテスト
特定のコンテナを必要とするアプリ（例：LaTeX用のPythonコンテナが必要なConcept Visualizer）の場合：
1. 必要なコンテナが実行中であることを確認: `./docker/monadic.sh check`
2. ローカル開発の場合、Rubyコンテナのみを停止
3. ローカルRubyコードを実行 - 他の実行中のコンテナと通信します
4. コンテナパス（`/monadic/data`）は自動的にホストパス（`~/monadic/data`）にマッピングされます

### Docker Composeプロジェクトの一貫性
Docker Composeコマンドを使用する際は、常にプロジェクト名フラグを使用して一貫性を確保してください：
```bash
docker compose -p "monadic-chat" [command]
```
これは特にパッケージ化されたElectronアプリで適切なコンテナ管理を維持するために重要です。

## ユーザー向け

コンテナをカスタマイズしたいユーザーは、以下の場所にカスタムスクリプトを配置する必要があります：
- Pythonのカスタマイズには`~/monadic/config/pysetup.sh`
- Rubyのカスタマイズには`~/monadic/config/rbsetup.sh`
- Ollamaモデルインストールには`~/monadic/config/olsetup.sh`

これらのユーザー提供スクリプトは、ローカルでコンテナをビルドする際に自動的に使用され、ビルドプロセス中にプレースホルダースクリプトを置き換えます。ただし、Gitリポジトリにはコミットされません。

