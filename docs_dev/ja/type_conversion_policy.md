# 型変換ポリシー

## 概要

このドキュメントは、Monadic ChatのRubyバックエンドとJavaScriptフロントエンド間の型変換ポリシーを定義します。このポリシーに従うことで、ブール値文字列が誤ってtruthyな値として評価されるなどの型関連のバグを防ぎます。

## アーキテクチャ

```
Ruby (MDSL/App Settings)
    ↓ JSONシリアライゼーション
WebSocket (JSON)
    ↓ JSONパース
JavaScript (Frontend)
```

## 型カテゴリ

### 1. ブール値機能フラグ

**目的**：UI機能とアプリの動作を有効/無効にする

**型要件**：ブール値として保持する必要があります（文字列ではない）

**影響を受けるパラメータ**：
- UI制御：`auto_speech`、`easy_submit`、`initiate_from_assistant`
- レンダリング：`mathjax`、`mermaid`、`abc`、`sourcecode`、`monadic`
- 機能：`image`、`pdf`、`pdf_vector_storage`、`websearch`
- 高度：`jupyter_access`、`jupyter`、`image_generation`、`video`

**Ruby実装**（`lib/monadic/utils/websocket.rb`）：
```ruby
# prepare_apps_dataメソッド内
elsif ["auto_speech", "easy_submit", "initiate_from_assistant",
       "mathjax", "mermaid", "abc", "sourcecode", "monadic",
       "image", "pdf", "pdf_vector_storage", "websearch",
       "jupyter_access", "jupyter", "image_generation", "video"].include?(p.to_s)
  # 機能フラグのブール値を保持
  # これらは適切なJavaScript評価のために文字列ではなく実際のブール値である必要があります
  apps[k][p] = m
```

**JavaScript実装**：
```javascript
// 防御的ブール値評価のためのグローバルヘルパー関数
window.toBool = (value) => {
  if (typeof value === 'boolean') return value;
  if (typeof value === 'string') return value === 'true';
  return !!value;
};

// loadParamsとproceedWithAppChangeでの使用
if (toBool(params["auto_speech"])) {
  // 機能を有効化
}
```

**これが重要な理由**：
```javascript
// 問題：文字列"false"はJavaScriptでtruthyです
if ("false") {  // ← trueと評価される！
  console.log("This runs!"); // ← 予期しない動作
}

// 解決策：実際のブール値を使用
if (false) {  // ← falseと評価される
  console.log("This does not run"); // ← 期待される動作
}
```

### 2. 配列とオブジェクトパラメータ

**目的**：複雑なデータ構造（モデルリスト、ツール定義）

**型要件**：JSONシリアライズする必要があります

**影響を受けるパラメータ**：
- `models`（文字列の配列）
- `tools`（配列またはツール定義のハッシュ）

**Ruby実装**：
```ruby
elsif p == "models" && m.is_a?(Array)
  apps[k][p] = m.to_json
elsif p == "tools" && (m.is_a?(Array) || m.is_a?(Hash))
  apps[k][p] = m.to_json
```

**JavaScript実装**：
```javascript
// 必要に応じてJSONをパース
const models = JSON.parse(apps[appValue]["models"]);
const tools = JSON.parse(apps[appValue]["tools"]);
```

### 3. 文字列パラメータ

**目的**：テキストコンテンツと識別子

**型要件**：文字列に変換（デフォルト動作）

**影響を受けるパラメータ**：
- `app_name`、`display_name`、`icon`、`description`
- `initial_prompt`、`system_prompt`
- `group`、`provider`

**Ruby実装**：
```ruby
# デフォルトケース - 文字列に変換
else
  apps[k][p] = m ? m.to_s : nil
end
```

### 4. 数値パラメータ

**目的**：モデル動作の数値設定

**型要件**：現在文字列に変換されますが、JavaScriptはこれを適切に処理します

**影響を受けるパラメータ**：
- `temperature`（Float）
- `context_size`（Integer）
- `max_tokens`（Integer）
- `reasoning_effort`（文字列だが概念的には順序付き）

**Ruby実装**：
```ruby
# 現在はデフォルトの文字列変換を使用
apps[k][p] = m ? m.to_s : nil
```

**JavaScript実装**：
```javascript
// 型強制は自動的に発生
const temperature = parseFloat(params["temperature"]);
const contextSize = parseInt(params["context_size"], 10);

// または数値コンテキストで直接使用（自動強制）
if ($("#temperature").val() > 0.5) { ... }
```

**将来の検討事項**：
明示的な数値比較が問題になる場合は、型保持リストに追加します：
```ruby
elsif ["temperature", "context_size", "max_tokens"].include?(p.to_s)
  apps[k][p] = m
```

### 5. 特殊ケース：disabled

**目的**：APIキーの存在に基づいてアプリの可用性を制御

**型要件**：互換性のため文字列である必要があります

**文字列である理由**：
- Rubyでブール式として評価：`!CONFIG["OPENAI_API_KEY"]`
- 表示目的で文字列としてフロントエンドに送信
- フロントエンドはtruthyをチェック

**Ruby実装**：
```ruby
elsif p == "disabled"
  # フロントエンドとの互換性のため、disabledを文字列として保持
  apps[k][p] = m.to_s
```

## 実装チェックリスト

新しいMDSLパラメータを追加する際：

- [ ] パラメータ型を決定（ブール値、配列、オブジェクト、文字列、数値）
- [ ] ブール値機能フラグの場合：`websocket.rb`の型保持リストに追加
- [ ] 配列/オブジェクトの場合：明示的な`.to_json`処理を追加
- [ ] 数値の場合：明示的な型保持が必要かどうかを検討
- [ ] 新しいパラメータでこのドキュメントを更新
- [ ] アプリ切り替え動作の統合テストを追加

## テスト戦略

### ユニットテスト

型変換を単独でテスト：
```ruby
# spec/unit/utils/websocket_type_conversion_spec.rb
describe "prepare_apps_data type conversion" do
  it "preserves boolean feature flags" do
    result = prepare_apps_data_for_test(auto_speech: false)
    expect(result["auto_speech"]).to be false
    expect(result["auto_speech"]).not_to eq "false"
  end
end
```

### 統合テスト

アプリ切り替え動作をテスト：
```ruby
# spec/integration/app_switching_spec.rb
it "resets feature flags when switching apps" do
  # Voice Chat (auto_speech: true)からChat (auto_speech: false)に切り替え
  # UIチェックボックスが正しい状態を反映することを確認
  # paramsハッシュが正しいブール値を持つことを確認
end
```

## 一般的な落とし穴

### ❌ しないこと：JavaScriptで文字列ブール値を信頼

```javascript
// 間違い
if (params["auto_speech"]) {
  // "false"はtruthyになります！
}
```

### ✅ すること：toBoolヘルパーを使用

```javascript
// 正しい
if (toBool(params["auto_speech"])) {
  // ブール値と文字列の両方を正しく処理
}
```

### ❌ しないこと：setParamsでブール値を文字列に変換

```javascript
// 間違い
params["mathjax"] = "true";
```

### ✅ すること：実際のブール値を使用

```javascript
// 正しい
params["mathjax"] = true;
```

### ❌ しないこと：型リストを更新せずに新しいブール値パラメータを追加

```ruby
# 間違い - 新しいパラメータは文字列化されます
features do
  my_new_boolean_flag true
end
```

### ✅ すること：型保持リストに追加

```ruby
# 正しい - websocket.rbに追加
elsif ["auto_speech", ..., "my_new_boolean_flag"].include?(p.to_s)
  apps[k][p] = m
```

## 後方互換性

`toBool`ヘルパー関数は後方互換性を保証します：

```javascript
// レガシー文字列値を処理
toBool("true")  → true
toBool("false") → false

// 現代のブール値を処理
toBool(true)    → true
toBool(false)   → false

// エッジケースを処理
toBool(null)    → false
toBool(undefined) → false
toBool(0)       → false
toBool(1)       → true
```

一部の既存のコードは明示的に文字列"true"をチェックします：
```javascript
if (params["pdf"] === "true" || params["pdf_vector_storage"] === true)
```

このパターンは後方互換性を提供し、存在する場合は維持する必要があります。

## 移行ガイド

型関連のバグに遭遇した場合：

1. **影響を受けるパラメータを特定**
   - 動作を切り替えるブール値かどうかを確認
   - ブラウザコンソールで現在の型を確認：`typeof params["param_name"]`

2. **型保持リストに追加**
   - `lib/monadic/utils/websocket.rb`を編集
   - elsif条件にパラメータ名を追加

3. **防御的チェックを追加**
   - パラメータが評価されるJavaScriptで`toBool()`を使用
   - `loadParams()`と`proceedWithAppChange()`の両方で

4. **徹底的にテスト**
   - さまざまな組み合わせでアプリ切り替えをテスト
   - UIのチェックボックス状態を確認
   - ブラウザコンソールでparamsハッシュを確認

5. **ドキュメントを更新**
   - このドキュメントにパラメータを追加
   - 必要に応じてMDSLドキュメントを更新

## 将来の改善

### 完了（2025-01）

- ✅ ブール値機能フラグの型保持
- ✅ 後方互換性のための`toBool`ヘルパー関数
- ✅ 型変換ポリシードキュメント
- ✅ MDSL型リファレンスドキュメント
- ✅ アプリ切り替えの統合テスト

### 中期的改善

#### 1. 数値パラメータの型保持

**現状**：数値パラメータ（`temperature`、`context_size`、`max_tokens`）は送信中に文字列に変換されます。

**提案される変更**：`websocket.rb`の型保持リストに数値パラメータを追加：

```ruby
elsif ["temperature", "context_size", "max_tokens"].include?(p.to_s)
  apps[k][p] = m  # 数値として保持
```

**メリット**：
- JavaScriptで`parseInt()`/`parseFloat()`が不要になる
- 型強制のエッジケースを防止
- データ型についてより明示的

**考慮事項**：
- 現在のシステムはJavaScriptの自動型強制により機能
- 変更はリスクが低いが、徹底的にテストする必要がある
- 明示的に文字列を期待するコードに影響を与える可能性がある

#### 2. JSDoc型アノテーション

**目標**：JavaScriptコードベースに包括的な型アノテーションを追加。

**スコープ**：
- `utilities.js`、`monadic.js`、`websocket.js`のすべてのパブリックAPI関数
- `apps`、`params`、`modelSpec`オブジェクトの型定義
- 関数パラメータと戻り値の型ドキュメント

**例**：
```javascript
/**
 * 複数の入力型からブール値を正規化
 * @param {boolean|string|*} value - ブール値に変換する値
 * @returns {boolean} - 正規化されたブール値
 */
window.toBool = (value) => {
  if (typeof value === 'boolean') return value;
  if (typeof value === 'string') return value === 'true';
  return !!value;
};
```

**メリット**：
- より良いIDE自動補完とエラー検出
- 自己文書化コード
- 潜在的なTypeScript移行の基盤

#### 3. 開発時型チェック

**目標**：開発モードでランタイム型検証を有効化。

**アプローチ**：
```javascript
// 開発ビルドに追加
if (CONFIG["DEVELOPMENT_MODE"]) {
  function validateAppSettings(appName, settings) {
    const booleanFlags = ["auto_speech", "easy_submit", ...];
    booleanFlags.forEach(flag => {
      if (settings[flag] !== undefined && typeof settings[flag] !== 'boolean') {
        console.error(`Type error: ${appName}[${flag}] should be boolean, got ${typeof settings[flag]}`);
      }
    });
  }
}
```

**メリット**：
- 開発中に型エラーをキャッチ
- 型変換バグの回帰を防止
- 本番環境でのパフォーマンス影響なし

### 長期的検討事項

#### 1. TypeScript移行

**現在の評価**：JavaScriptコードベースは大規模で複雑。

**段階的アプローチ**：
- TypeScriptで新しいモジュールを開始
- 既存モジュールに`.d.ts`型定義ファイルを追加
- 重要なモジュール（ユーティリティ、websocket）を徐々に変換
- `allowJs`を使用して後方互換性を維持

**メリット**：
- 強力なコンパイル時型チェック
- より良いリファクタリングサポート
- ランタイムエラーの削減

**課題**：
- 大規模なコードベース変換の労力
- ビルドツールの複雑さ
- チームトレーニング要件

#### 2. ランタイム型検証

**目標**：システムを流れるすべてのデータの包括的なランタイム検証。

**検討すべきライブラリ**：
- Zod（スキーマ検証）
- io-ts（ランタイム型チェック）
- Joi（オブジェクトスキーマ検証）

**スコープ**：
- WebSocketメッセージ検証
- アプリ設定検証
- ユーザー入力検証
- APIレスポンス検証

**例**：
```javascript
const AppSettingsSchema = z.object({
  auto_speech: z.boolean(),
  easy_submit: z.boolean(),
  temperature: z.number().min(0).max(2),
  model: z.array(z.string()),
  // ...
});

// 使用前に検証
const settings = AppSettingsSchema.parse(rawSettings);
```

**メリット**：
- データ破損を早期にキャッチ
- より良いエラーメッセージ
- スキーマを通じたドキュメント

#### 3. 自動型一貫性テスト

**目標**：自動テストを通じて型一貫性の回帰を防止。

**テストカテゴリ**：

**a) プロパティベーステスト**：
```ruby
# spec/property/type_consistency_spec.rb
RSpec.describe "Type Consistency Properties" do
  it "all boolean feature flags remain boolean through serialization" do
    boolean_flags.each do |flag|
      app_data = prepare_apps_data
      app_data.values.each do |settings|
        next unless settings[flag]
        expect(settings[flag]).to satisfy { |v|
          v.is_a?(TrueClass) || v.is_a?(FalseClass)
        }
      end
    end
  end
end
```

**b) ラウンドトリップテスト**：
```javascript
// test/type_roundtrip.test.js
describe('Type Round-Trip', () => {
  it('preserves types through Ruby → JSON → JavaScript', async () => {
    const original = {
      auto_speech: false,
      temperature: 0.7,
      models: ["gpt-5", "gpt-4.1"]
    };

    // 完全なラウンドトリップをシミュレート
    const afterRuby = simulateRubySerialization(original);
    const afterJSON = JSON.parse(JSON.stringify(afterRuby));
    const afterJS = loadParams(afterJSON);

    expect(typeof afterJS.auto_speech).toBe('boolean');
    expect(typeof afterJS.temperature).toBe('number');
    expect(Array.isArray(afterJS.models)).toBe(true);
  });
});
```

**c) コントラクトテスト**：
```ruby
# spec/contracts/websocket_contract_spec.rb
RSpec.describe "WebSocket Contract" do
  it "maintains type contract for app switching messages" do
    contract = {
      type: "load",
      apps: {
        "ChatOpenAI" => {
          auto_speech: Boolean,
          models: Array,
          temperature: Numeric
        }
      }
    }

    verify_contract(actual_message, contract)
  end
end
```

## 関連ドキュメント

- `docs_dev/common-issues.md` - トラブルシューティングガイド
- `docs/advanced-topics/monadic_dsl.md` - MDSL構文リファレンス
- `docs_dev/app_isolation_and_session_safety.md` - セッション安全性ガイドライン
- `docs_dev/mdsl/mdsl_type_reference.md` - MDSL型定義

## 改訂履歴

- 2025-01：ブール値機能フラグ修正後の初期ドキュメント
- 2025-01：中期および長期計画を含む将来の改善セクションを追加
- 影響を受ける機能フラグ：すべての16個のブール値パラメータ
- 変更されたファイル：`websocket.rb`、`utilities.js`、`monadic.js`、`websocket.js`
