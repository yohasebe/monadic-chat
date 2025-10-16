# アプリの分離とセッション安全性

## 概要

Monadic Chatは共有インスタンスアーキテクチャを使用しており、各アプリクラスはグローバルな`APPS`ハッシュに保存された単一のインスタンスを持ちます。この設計は効率的ですが、セッション間のデータ汚染を防ぐためにインスタンス変数の慎重な取り扱いが必要です。

## アーキテクチャ

### アプリインスタンスのライフサイクル

```ruby
# lib/monadic.rb:987-998
def init_apps
  apps = {}
  klass = Object.const_get("MonadicApp")

  klass.subclasses.each do |a|
    app = a.new  # ← クラスごとに単一インスタンス
    # ...
    apps[app_name] = app  # ← すべてのセッションで共有
  end
end

APPS = init_apps  # ← グローバル定数
```

**重要な影響**：
- `APPS["Chord Accompanist"]`はすべてのユーザーに対して**同じインスタンス**を返す
- インスタンス変数（`@context`、`@api_key`、`@settings`など）はすべてのセッション間で**共有される**
- 複数のユーザーが同時に同じアプリにアクセスすると競合状態が発生する可能性がある

### 安全なパターンと安全でないパターン

#### ✅ 安全：純粋関数（推奨）

```ruby
class MyApp < MonadicApp
  def my_tool(input:, options:)
    # パラメータのみを使用 - インスタンス変数を使用しない
    result = process_input(input, options)

    format_tool_response(
      success: true,
      output: result
    )
  end

  private

  def process_input(input, options)
    # 純粋関数 - 同じ入力は常に同じ出力を生成
    # 副作用なし、インスタンス変数アクセスなし
    input.upcase if options[:uppercase]
  end
end
```

**安全な理由**：
- 呼び出し間で共有状態がない
- 設計上スレッドセーフ
- 競合状態が発生しない

#### ⚠️ 安全でない：インスタンス変数の状態

```ruby
class MyApp < MonadicApp
  def validate_code(code:)
    # 誤り：セッション固有のデータをインスタンス変数に保存
    @last_validated_code = code
    @validation_timestamp = Time.now

    # ユーザーAのコードがユーザーBによって上書きされる可能性がある
    result = validate(code)

    { success: result }
  end

  def preview_code
    # 誤り：共有インスタンス変数を読み取り
    code = @last_validated_code  # ← 別のユーザーのものかもしれない！
    generate_preview(code)
  end
end
```

**安全でない理由**：
- ユーザーAが`validate_code("A's code")`を呼び出す
- ユーザーBが`validate_code("B's code")`を呼び出す → `@last_validated_code`を上書き
- ユーザーAが`preview_code`を呼び出す → Bのコードを取得！

## 実装された安全対策

### 1. app_nameによるメッセージの分離

**実装**：`lib/monadic/utils/websocket.rb:313-315, 523-526, 1163-1169`

```ruby
# app_nameでメッセージを保存
new_data = {
  "mid" => SecureRandom.hex(4),
  "role" => "assistant",
  "text" => text,
  "html" => html,
  "app_name" => session["parameters"]["app_name"],  # ← 追加
  "active" => true
}
session[:messages] << new_data

# app_nameでフィルタリングしてメッセージを読み込み
current_app_name = session["parameters"]["app_name"]
messages = session[:messages].filter { |m|
  m["type"] != "search" && m["app_name"] == current_app_name  # ← フィルタリング
}
```

**防止する問題**：アプリ間の会話の漏洩（例：異なるアプリインスタンスが互いのメッセージを見る）

### 2. アプリごとのエンベディングデータベース

**実装**：`lib/monadic/app.rb:162-176`

```ruby
def ensure_embeddings_db
  if @embeddings_db.nil? && defined?(TextEmbeddings)
    # アプリごとのデータベース名を使用してアプリ間の混在を回避
    app_key = begin
      self.class.name.to_s.strip.downcase.gsub(/[^a-z0-9_\-]/, '_')
    rescue StandardError
      'default'
    end
    base = "monadic_user_docs"
    db_name = "#{base}_#{app_key}"  # ← アプリ固有のDB
    @embeddings_db = TextEmbeddings.new(db_name, recreate_db: false)
  end
  @embeddings_db
end
```

**防止する問題**：アプリ間のドキュメント混在（例：PDF Navigatorのドキュメントが別のアプリの検索に表示される）

### 3. アプリ固有のシステムプロンプト

**実装**：各アプリはクラス設定に独自のシステムプロンプトを保存

```ruby
# プロンプトキャッシングはアプリ固有のシステムプロンプトを使用
system_prompt = APPS[app_name].settings["initial_prompt"]
```

**防止する問題**：アプリ間のプロンプトキャッシュ汚染

## ケーススタディ

### ケーススタディ1：Mermaid Grapher（2025-01修正）

**元の問題**：
```ruby
def run_full_validation(code, source: nil)
  # ...
  @context[:mermaid_last_validation_ok] = true      # ← 安全でない
  @context[:mermaid_last_validated_code] = code     # ← 安全でない
end
```

**問題点**：
- ユーザーAがMermaidコードを検証
- ユーザーBが異なるコードを検証 → `@context`を上書き
- ユーザーAがプレビューを要求 → 誤った検証状態を取得

**修正**（`apps/mermaid_grapher/mermaid_grapher_tools.rb:314-335`）：
```ruby
def run_full_validation(code, source: nil)
  # @contextの使用を完全に削除
  # 検証ワークフローはLLMが正しいシーケンスに従うことに依存
  result[:validated_code] = code
  result
end
```

### ケーススタディ2：AutoForge（2025-01修正）

**元の問題**：
```ruby
def generate_application(params = {})
  context = @context || {}              # ← 安全でない
  @context ||= context                  # ← 安全でない

  # プロジェクト情報を保存
  @context[:auto_forge] = project_info  # ← 安全でない
end
```

**問題点**：
- ユーザーAがプロジェクト「AppA」を作成
- ユーザーBがプロジェクト「AppB」を作成 → `@context[:auto_forge]`を上書き
- ユーザーAの後続の操作が「AppB」のデータを使用

**修正**（`apps/auto_forge/auto_forge_tools.rb:88-94, 201-212`）：
```ruby
def generate_application(params = {})
  # ローカル変数のみを使用
  context = {}                          # ← 安全

  # ジェネレーターに渡すローカルコンテキストに保存
  context[:auto_forge] = project_info   # ← 安全（ローカルスコープ）
  # @context代入を削除
end
```

## アプリ開発のベストプラクティス

### すべきこと ✅

1. **ツールメソッドに純粋関数を使用**
   ```ruby
   def my_tool(input:, param1:, param2:)
     result = process(input, param1, param2)
     format_tool_response(result)
   end
   ```

2. **関数パラメータを通じてデータを渡す**
   ```ruby
   def helper_method(data, options)
     # すべての入力をパラメータとして
     # 戻り値、副作用なし
   end
   ```

3. **ユーザー固有の状態にRackセッションを使用**
   ```ruby
   def my_tool(input:)
     # Thread.current[:rack_session]はセッション固有
     session = Thread.current[:rack_session]
     session[:my_app_data] ||= {}
     # セッションストレージを使用
   end
   ```

4. **永続的な状態にファイルシステムを使用**
   ```ruby
   def save_project(project_id:, data:)
     # ファイルベースのストレージは自然に分離される
     path = File.join(SHARED_VOL, project_id, "state.json")
     File.write(path, JSON.generate(data))
   end
   ```

### すべきでないこと ❌

1. **セッション固有のデータをインスタンス変数に保存しない**
   ```ruby
   # ❌ 誤り
   def my_tool(input:)
     @user_input = input        # 共有される！
     @session_id = SecureRandom.hex
   end
   ```

2. **ツール呼び出し間でインスタンス変数の状態に依存しない**
   ```ruby
   # ❌ 誤り
   def step1(data:)
     @step1_result = process(data)
   end

   def step2
     use(@step1_result)  # 別のユーザーのものかもしれない！
   end
   ```

3. **セッション固有の状態に@contextを使用しない**
   ```ruby
   # ❌ 誤り
   def my_tool(input:)
     @context ||= {}
     @context[:user_data] = input
   end
   ```

4. **ツールメソッド内で@api_key、@settings、@embeddings_dbを変更しない**
   ```ruby
   # ❌ 誤り
   def my_tool(api_key:)
     @api_key = api_key  # すべてのユーザーに影響！
   end
   ```

## インスタンス変数の許容される使用

### 読み取り専用のクラス設定

```ruby
class MyApp < MonadicApp
  def initialize
    super
    @config = load_app_config  # ✅ OK：読み取り専用、すべてのユーザーで同じ
  end

  def my_tool(input:)
    # 読み取り専用設定に@configを使用することは問題ない
    process(input, max_length: @config[:max_length])
  end
end
```

### リクエストごとの一時的な状態（高度）

```ruby
def complex_tool(input:)
  # ⚠️ 許容可能：インスタンス変数のスコープが単一メソッド実行に限定
  # Rubyの実行モデルを理解している場合のみ
  @temp_data = expensive_computation(input)
  result1 = use_temp_data_part1
  result2 = use_temp_data_part2
  @temp_data = nil  # クリーンアップ

  { result1: result1, result2: result2 }
end
```

**警告**：このパターンは脆弱であり、パフォーマンスのために必要な場合を除いて避けるべきです。

## セッション安全性のテスト

### 手動テストチェックリスト

1. **同時ユーザーシミュレーション**：
   - 異なるアプリで2つのブラウザウィンドウを開く
   - 交互のシーケンスで操作を実行
   - データの混在が発生しないことを確認

2. **状態検査**：
   - インスタンス変数アクセスを追跡するデバッグログを追加
   - 予期しない状態変更を監視
   - 競合状態をチェック

3. **セッション境界テスト**：
   - 同じセッション内でアプリを切り替える
   - メッセージが漏洩しないことを確認
   - コンテキストが適切に分離されていることを確認

### 自動テスト（将来）

```ruby
# spec/integration/app_isolation_spec.rb（例）
RSpec.describe "App Isolation" do
  it "prevents state contamination between concurrent users" do
    # ユーザーAをシミュレート
    session_a = create_session(app: "AppA")
    result_a1 = call_tool(session_a, :my_tool, input: "A's data")

    # ユーザーBをシミュレート
    session_b = create_session(app: "AppA")
    result_b = call_tool(session_b, :my_tool, input: "B's data")

    # ユーザーAが続行
    result_a2 = call_tool(session_a, :related_tool)

    # 汚染がないことを確認
    expect(result_a2).not_to include("B's data")
  end
end
```

## まとめ

**重要な原則**：アプリインスタンスを**ステートレスサービスオブジェクト**として扱う。すべてのセッション固有のデータは次を通じて流れる必要がある：
- 関数パラメータ（推奨）
- Rackセッションストレージ
- ファイルシステム
- データベース

`MonadicApp`サブクラスのインスタンス変数にセッション固有のデータを保存**しない**でください。

## 関連ドキュメント

- `docs_dev/common-issues.md` - トラブルシューティングガイド
- `docs_dev/developer/development_workflow.md` - 公開開発者ガイドライン
- `lib/monadic/app.rb` - MonadicApp基本クラス
- `lib/monadic/utils/websocket.rb` - セッション管理
