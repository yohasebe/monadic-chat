# Progressive Tool Disclosure (PTD)

## 概要

Progressive Tool Disclosure (PTD) は、実行時の条件に基づいてツールの可用性を動的に制御するアーキテクチャパターンです。ツールは依存関係が満たされている場合にのみ表示・利用可能となり、エラーや混乱を防ぐことでユーザー体験を向上させます。

## アーキテクチャ

### コアコンポーネント

1. **共有ツールグループ** (`lib/monadic/shared_tools/`)
   - 関連するツールの再利用可能なコレクション
   - 各グループは実行時チェック用の `available?` クラスメソッドを持つ
   - ツールは一度定義され、複数のアプリでインポートされる

2. **レジストリ** (`lib/monadic/shared_tools/registry.rb`)
   - 全共有ツールグループの中央レジストリ
   - 可視性ルール（`always` または `conditional`）を管理
   - リアルタイムチェック用の `available?(group)` メソッドを提供

3. **DSL統合** (`lib/monadic/dsl.rb`)
   - MDSLファイル用の `import_shared_tools` ディレクティブ
   - ツール競合防止のための重複検出
   - UI表示用のメタデータ追跡

4. **WebSocket通信** (`lib/monadic/utils/websocket.rb`)
   - 可用性ステータスを含むツールグループメタデータを送信
   - Web UIへのリアルタイム更新

5. **Web UI表示** (`public/js/monadic/utilities.js`)
   - 可視性インジケータ付きツールグループバッジ
   - 可用性に基づく条件付きレンダリング

### 可視性モード

- **`always`**: ツールグループは常に利用可能
  - 例: `file_operations`, `python_execution`
  - 実行時チェック不要

- **`conditional`**: ツールグループの可用性は実行時条件に依存
  - 例: `web_automation`（Seleniumコンテナが必要）
  - レジストリの `available_when` ラムダ経由でチェック

## 実装

### 1. 共有ツールグループの作成

```ruby
# lib/monadic/shared_tools/example_group.rb
module Monadic
  module SharedTools
    module ExampleGroup
      # 可用性チェック（条件付き可視性用）
      def self.available?
        # 依存関係が満たされているかチェック
        system("docker ps | grep -q example-container")
      end

      # ツール定義
      TOOLS = [
        {
          type: "function",
          function: {
            name: "example_tool",
            description: "ツールの説明",
            parameters: {
              type: "object",
              properties: {
                param1: {
                  type: "string",
                  description: "パラメータの説明"
                }
              },
              required: ["param1"]
            }
          }
        }
      ].freeze
    end
  end
end
```

### 2. ツールグループの登録

```ruby
# lib/monadic/shared_tools/registry.rb
TOOL_GROUPS = {
  example_group: {
    module_ref: MonadicSharedTools::ExampleGroup,
    visibility: 'conditional',
    available_when: -> { MonadicSharedTools::ExampleGroup.available? }
  }
}.freeze
```

### 3. MDSLでの使用

```ruby
# apps/my_app/my_app_provider.mdsl
MonadicApp.register "MyAppProvider" do
  llm do
    provider "provider_name"
    model "model-name"
  end

  # 条件付き可視性で共有ツールをインポート
  import_shared_tools :example_group, visibility: "conditional"

  # アプリ固有のツールも定義可能
  tools do
    define_tool "app_specific_tool", "説明" do
      parameter :param1, "string", "パラメータの説明", required: true
    end
  end
end
```

### 4. ツールメソッドの実装

```ruby
# apps/my_app/my_app_tools.rb
module MyAppTools
  include MonadicHelper
  include MonadicSharedTools::ExampleGroup

  # ツールメソッドの実装
  def example_tool(params)
    # 実装をここに
  end
end

class MyAppProvider < MonadicApp
  include ProviderHelper
  include MyAppTools
end
```

## パフォーマンス最適化

### キャッシング

負荷の高い可用性チェックを持つツールグループはキャッシングを実装すべきです：

```ruby
module Monadic
  module SharedTools
    module WebAutomation
      @availability_cache ||= { ts: Time.at(0), available: false }

      def self.available?
        # 有効期間内（10秒TTL）であればキャッシュ結果を返す
        if (Time.now - @availability_cache[:ts]) <= 10
          return @availability_cache[:available]
        end

        # 実際のチェックを実行
        containers = `docker ps --format "{{.Names}}"`
        available = containers.include?("selenium-container")

        # キャッシュを更新
        @availability_cache = { ts: Time.now, available: available }
        available
      end
    end
  end
end
```

**理由**: キャッシングなしでは、可用性チェックはアプリリストリクエストごとに実行されます。同じツールグループをインポートする7つのアプリがある場合、リクエストごとに7回の `docker ps` 呼び出しが発生します。キャッシングにより、これを10秒あたり1回の呼び出しに削減できます。

## 既存のツールグループ

### 常時利用可能

1. **`jupyter_operations`** (12ツール)
   - Jupyterノートブック管理
   - セル操作、ノートブック作成

2. **`python_execution`** (4ツール)
   - Pythonコンテナでのコード実行
   - 環境チェック

3. **`file_operations`** (3ツール)
   - ファイル書き込み、一覧表示、削除
   - 共有フォルダ操作

4. **`file_reading`** (3ツール)
   - テキスト、PDF、Officeファイルの読み込み
   - 共有フォルダファイルアクセス

### 条件付き利用可能

1. **`web_automation`** (4ツール)
   - 必要: SeleniumおよびPythonコンテナ
   - スクリーンショットキャプチャ、Webスクレイピング
   - 使用アプリ: Visual Web Explorer、AutoForge

2. **`video_analysis_openai`** (1ツール)
   - 必要: OpenAI APIキー
   - 動画コンテンツ分析

## メリット

1. **ユーザー体験**
   - 依存関係が欠けている場合の混乱するエラーがない
   - UIバッジによる利用不可機能の明確な表示

2. **コードの再利用**
   - ツール定義の単一の真実の源（Single Source of Truth）
   - 7つのアプリで92行の重複コードを削減

3. **保守性**
   - ツール更新が全アプリに自動伝播
   - 一貫したエラーメッセージと動作

4. **スケーラビリティ**
   - 新しいツールグループの追加が容易
   - 既存ツールを使用する新しいアプリの追加が簡単

## マイグレーションガイド

### 既存アプリを共有ツールに変換

**変更前:**
```ruby
# apps/my_app/my_app_provider.mdsl
tools do
  define_tool "capture_screenshot", "スクリーンショットをキャプチャ" do
    parameter :url, "string", "キャプチャするURL", required: true
  end

  define_tool "scrape_page", "ページコンテンツをスクレイピング" do
    parameter :url, "string", "スクレイピングするURL", required: true
  end
end
```

**変更後:**
```ruby
# apps/my_app/my_app_provider.mdsl
import_shared_tools :web_automation, visibility: "conditional"
```

**ツールファイルの変更:**
```ruby
# 変更前: apps/my_app/my_app_tools.rb
module MyAppTools
  def capture_screenshot(params)
    # 実装
  end

  def scrape_page(params)
    # 実装
  end
end

# 変更後: 実装を共有モジュールに移動
# lib/monadic/shared_tools/web_automation.rb
module Monadic::SharedTools::WebAutomation
  def capture_screenshot(params)
    # 実装
  end

  def scrape_page(params)
    # 実装
  end
end

# apps/my_app/my_app_tools.rb
module MyAppTools
  include MonadicSharedTools::WebAutomation
end
```

## テスト

### ユニットテスト

ツールグループの可用性ロジックをテスト：

```ruby
RSpec.describe "WebAutomation Tool Group" do
  describe ".available?" do
    it "コンテナが実行中の場合trueを返す" do
      allow_any_instance_of(Kernel).to receive(:`).and_return("selenium-container\npython-container")
      expect(Monadic::SharedTools::WebAutomation.available?).to be true
    end

    it "コンテナが欠けている場合falseを返す" do
      allow_any_instance_of(Kernel).to receive(:`).and_return("")
      expect(Monadic::SharedTools::WebAutomation.available?).to be false
    end
  end
end
```

### 統合テスト

利用不可ツールが役立つエラーを返すことをテスト：

```ruby
it "Seleniumが利用不可の場合に役立つエラーを提供する" do
  result = app.capture_screenshot(url: "https://example.com")
  expect(result[:error]).to include("Seleniumコンテナが実行されていません")
  expect(result[:suggestion]).to include("Seleniumコンテナを起動してください")
end
```

## 将来の拡張

1. **動的ツールロード**
   - 必要な時のみツールグループをロード
   - 多数の条件付きツールを持つアプリのメモリフットプリント削減

2. **ユーザー設定**
   - 特定のツールグループの無効化を許可
   - カスタムツールグループ可視性設定

3. **依存チェーン検出**
   - 推移的依存関係の自動チェック
   - ツールグループ間の依存がある場合の警告

4. **ヘルスモニタリング**
   - バックグラウンドでの定期的可用性チェック
   - 依存関係が利用不可になった場合のプロアクティブ通知

## 関連ドキュメント

- `docs_dev/developer/code_structure.md` - 全体アーキテクチャ
- `docs/advanced-topics/monadic_dsl.md` - MDSL構文リファレンス
- `docs_dev/ruby_service/gemini_tool_continuation_fix.md` - ツールフォーマット処理
