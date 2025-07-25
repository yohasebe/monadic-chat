# 開発ワークフロー

このドキュメントには、Monadic Chatプロジェクトに貢献する開発者向けのガイドラインと指示が含まれています。

?> このドキュメントは、Monadic Chat のレシピファイルの開発者ではなく、Monadic Chat自体の開発者向けです。

## テスト :id=testing

### テストフレームワーク :id=test-frameworks
- **JavaScript**: フロントエンドコードのテストにJestを使用
- **Ruby**: バックエンドコードのテストにRSpecを使用

### テスト構造 :id=test-structure
- JavaScriptテストは `test/frontend/` に配置
- Rubyテストは `docker/services/ruby/spec/` に配置（約64ファイル）
  - ユニットテスト: `spec/unit/` - 高速で独立したテスト（26ファイル）
  - 統合テスト: `spec/integration/` - Dockerサービスとの連携テスト（13ファイル）
  - システムテスト: `spec/system/` - アプリ検証テスト（2ファイル）
  - E2Eテスト: `spec/e2e/` - WebSocketを使用した完全なワークフローテスト（16ファイル、一部統合済み）
- アプリ固有の診断スクリプトは `docker/services/ruby/scripts/diagnostics/apps/{app_name}/` に配置
- Jestの設定は `jest.config.js` に定義
- JavaScriptのグローバルテスト設定は `test/setup.js` に定義

!> **注意:** E2Eテストは `with_e2e_retry(max_attempts: 3, wait: 10)` の形式を使用する必要があります。

### アプリ固有の診断スクリプト :id=app-specific-test-scripts
特定のテストや診断が必要なアプリケーションの場合：
- 診断スクリプトは診断ディレクトリに配置: `docker/services/ruby/scripts/diagnostics/apps/{app_name}/`
- 説明的な名前を使用: `test_feature_name.sh` または `diagnose_issue.rb`
- アプリ固有の診断スクリプトをプロジェクトルートディレクトリに配置しない
- 例: Concept Visualizerの診断スクリプトは `docker/services/ruby/scripts/diagnostics/apps/concept_visualizer/` に配置

!> **重要:** 診断スクリプトは `apps/{app_name}/test/` ディレクトリに配置してはいけません。アプリ内の `test/` サブディレクトリ内のファイルは、テストスクリプトがアプリケーションとしてロードされるのを防ぐため、アプリロード時に無視されます。

### テスト実行方法 :id=running-tests

?> **注意:** `rake server:debug`を使用して開発する場合、RubyテストはローカルのRuby環境を使用してホスト上で直接実行されます。開発環境ではRubyコンテナは使用されません。

#### 開発環境
- **Rubyコンテナ**: 使用しません - ローカルのRuby環境を使用
- **その他のコンテナ**: Python、PostgreSQL、Seleniumコンテナは起動している必要があります
- **スクリプト**: CLIツールとスクリプトは`docker/services/ruby/scripts/`からローカルで実行されます

#### Rubyテスト
```bash
# すべてのRubyテストを実行
rake spec

# 特定のテストカテゴリを実行
rake spec_unit        # ユニットテストのみ（高速）
rake spec_integration # 統合テスト
rake spec_system      # システムテスト
rake spec_e2e         # E2Eテスト（サーバー起動が必要）

# パターンに一致するテストを実行
bundle exec rspec spec/unit/*_spec.rb
```

#### E2Eテスト
E2Eテストはサーバーが動作している必要があります：
```bash
# 自動セットアップ付きですべてのE2Eテストを実行
rake spec_e2e

# このrakeタスクは自動的に：
# - Dockerコンテナが動作していることを確認
# - 必要に応じてサーバーを起動
# - すべてのE2Eテストを実行
# - プロバイダーカバレッジサマリーを表示
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

### テストの構成 :id=test-organization

テストは重複を最小限に抑え、保守性を向上させるように構成されています：

- **ユニットテスト** (`spec/unit/`): 外部依存関係のない高速で独立したテスト
- **統合テスト** (`spec/integration/`): 
  - `docker_infrastructure_spec.rb` - コンテナヘルス、Dockerコマンド、データベース接続
  - `app_helpers_integration_spec.rb` - ヘルパーモジュールとアプリ機能
- **システムテスト** (`spec/system/`): アプリ検証とMDSL検証
- **E2Eテスト** (`spec/e2e/`): 実際のAPIコールを使用した完全なワークフローテスト


## デバッグシステム :id=debug-system

Monadic Chatは環境変数で制御される統一デバッグシステムを使用します：

### デバッグカテゴリ :id=debug-categories
- `all`: すべてのデバッグメッセージ
- `app`: 一般的なアプリケーションデバッグ
- `embeddings`: テキストエンベディング操作
- `mdsl`: MDSLツール補完
- `tts`: テキスト読み上げ操作
- `drawio`: DrawIOグラファー操作
- `ai_user`: AIユーザーエージェント
- `web_search`: Web検索操作（Tavilyを含む）
- `api`: APIリクエストとレスポンス

### デバッグレベル :id=debug-levels
- `none`: デバッグ出力なし（デフォルト）
- `error`: エラーのみ
- `warning`: エラーと警告
- `info`: 一般情報
- `debug`: 詳細なデバッグ情報
- `verbose`: 生データを含むすべて

### エラー処理の改善 :id=error-handling-improvements
- **エラーパターン検出**: システムは繰り返されるエラーを自動検出し、3回目以降停止
- **UTF-8エンコーディング**: すべてのレスポンスがフォールバックエンコーディング置換で適切に処理
- **無限ループ防止**: 「Maximum function call depth exceeded」エラーを防ぐためツール呼び出しを制限
- **正常な劣化**: APIキーがない場合はクラッシュではなく明確なエラーメッセージを表示

### 使用例 :id=setup-usage-examples
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


## MDSL開発のベストプラクティス :id=mdsl-best-practices-section

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

**ツール検証：**
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


## 重要：セットアップスクリプトの管理 :id=managing-setup-scripts

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

### Gitプリコミットフック（オプション） :id=git-precommit-hook

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

## 開発環境のセットアップ :id=development-environment-setup

### 開発用にMonadic Chatを実行する :id=running-for-development

開発目的では、ElectronアプリなしでMonadic Chatを実行できます：

```bash
rake server:debug
```

このコマンドは：
- `EXTRA_LOGGING=true`でデバッグモードでサーバーを起動（rake server:debugコマンドにより自動設定）
- Rubyコンテナは起動せず、ホストのRubyランタイムを使用
- 他のすべてのコンテナを起動（Python、PostgreSQL、pgvector、利用可能な場合はOllama）
- ホスト上の`/docker/services/ruby/`のファイルを直接使用
- ブラウザで[http://localhost:4567](http://localhost:4567)からWeb UIにアクセス可能

このセットアップにより以下が可能になります：
- コンテナを再ビルドせずにRubyコードを編集して即座に変更を確認
- ローカルのRuby開発ツール（デバッガ、リンターなど）を使用
- ブラウザインターフェースで変更を素早くテスト
- 必要な他のサービスはコンテナで実行を維持


### コンテナを使用したローカル開発 :id=local-development-containers
コンテナ機能を使用しながらローカルで開発する場合：
- **Rubyコンテナ**: ローカルRuby環境を使用するために停止可能
- **その他のコンテナ**: 依存するアプリのために実行を継続する必要がある
- **Pythonコンテナ**: LaTeXを使用するConcept VisualizerやSyntax Treeなどのアプリに必要
- **パス**: `Monadic::Utils::Environment`モジュールにより自動調整

### コンテナ依存アプリのテスト :id=testing-container-dependencies
特定のコンテナを必要とするアプリ（例：LaTeX用のPythonコンテナが必要なConcept Visualizer）の場合：
1. 必要なコンテナが実行中であることを確認: `./docker/monadic.sh check`
2. ローカル開発の場合、Rubyコンテナのみを停止
3. ローカルRubyコードを実行 - 他の実行中のコンテナと通信します
4. コンテナパス（`/monadic/data`）は自動的にホストパス（`~/monadic/data`）にマッピングされます

### Docker Composeプロジェクトの一貫性 :id=docker-compose-consistency
Docker Composeコマンドを使用する際は、常にプロジェクト名フラグを使用して一貫性を確保してください：
```bash
docker compose -p "monadic-chat" [command]
```
これは特にパッケージ化されたElectronアプリで適切なコンテナ管理を維持するために重要です。

## ユーザー向け :id=for-users

コンテナをカスタマイズしたいユーザーは、以下の場所にカスタムスクリプトを配置する必要があります：
- Pythonのカスタマイズには`~/monadic/config/pysetup.sh`
- Rubyのカスタマイズには`~/monadic/config/rbsetup.sh`
- Ollamaモデルインストールには`~/monadic/config/olsetup.sh`

これらのユーザー提供スクリプトは、ローカルでコンテナをビルドする際に自動的に使用され、ビルドプロセス中にプレースホルダースクリプトを置き換えます。ただし、Gitリポジトリにはコミットされません。

