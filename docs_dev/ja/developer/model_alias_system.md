# モデルエイリアスとバージョンフィルタリングシステム

## 概要

Monadic Chatは、洗練されたモデルエイリアスとバージョンフィルタリングシステムを実装しています：
- モデル名のエイリアス機能により`model_spec.js`の重複を削減
- 日付付きモデル名を自動的にベース仕様に解決
- Web UIに関連バージョンのみを表示するようモデルリストをフィルタリング
- 複数のAIプロバイダーの日付フォーマットをサポート

## アーキテクチャ

### 3層システム

1. **model_spec.js (仕様レイヤー)**
   - ベースモデルの仕様を含む（通常は日付なしバージョン）
   - 仕様が異なる場合は日付付きバージョンも含む
   - モデル機能のSingle Source of Truth

2. **プロバイダーAPIレイヤー**
   - 各プロバイダーのAPIから利用可能なモデルを取得
   - 実際に使用できるモデル名を返す
   - 日付付き・日付なし両方のバージョンを含む場合がある

3. **表示レイヤー (Web UI)**
   - ユーザーに表示するモデルをフィルタリング
   - 各ベースモデルの日付なしバージョン + 最新の日付付きバージョンを表示
   - プロバイダーのAPI応答に存在するモデルのみを表示

## モデル名の正規化

### サポートされる日付フォーマット

システムは7種類の日付フォーマットを認識・解析します：

| フォーマット | 例 | プロバイダー | 備考 |
|--------|---------|----------|-------|
| `YYYY-MM-DD` | `gpt-4o-2024-11-20` | OpenAI, xAI | 最も一般的 |
| `YYYYMMDD` | `claude-3-7-sonnet-20250219` | Claude | 8桁の日付 |
| `MM-YYYY` | `command-r7b-12-2024` | Cohere | 月-年フォーマット |
| `YYMM` | `magistral-small-2509` | Mistral | 2桁年+月（2509 = 2025年9月） |
| `MM-DD` | `gemini-2.5-flash-lite-06-17` | Gemini | 月-日フォーマット |
| `exp-MMDD` | `gemini-2.0-flash-thinking-exp-1219` | Gemini | 実験的ビルド |
| `-NNN` | `gemini-2.0-flash-001` | Gemini | 連番バージョン番号 |

### 日付の検証

システムは日付サフィックスを検証してバージョン番号と区別します：

```javascript
// 有効な日付: 検証を通過
magistral-small-2509  // YYMM: 25 (2025年) は有効、09 (9月) は有効

// 日付ではない: 検証失敗
gpt-4.1               // 4.1 はバージョン番号
c4ai-aya-vision-32b   // 32b はパラメータサイズ
```

検証ルール:
- 年の範囲: 2020-2030
- 月の範囲: 1-12
- 日の範囲: 1-31

## エイリアス解決プロセス

### Ruby側

```ruby
# 1. モデル名の正規化（日付サフィックスを削除）
normalize_model_name("gpt-5-2025-08-07")  # => "gpt-5"

# 2. エイリアス解決（日付付きバージョンがspecにない場合はベースモデルにフォールバック）
resolve_model_alias("gpt-5-2025-08-07")   # => "gpt-5"

# 3. 仕様取得（自動的に解決された名前を使用）
get_model_spec("gpt-5-2025-08-07")        # => "gpt-5"の仕様
```

**実装**: `docker/services/ruby/lib/monadic/utils/model_spec.rb`

### JavaScript側

```javascript
// 1. 日付情報の抽出
extractDateSuffix("gpt-5-2025-08-07")
// => { dateString: "2025-08-07", parsedDate: Date, format: "YYYY-MM-DD" }

// 2. ベースモデル名の取得
getBaseModelName("gpt-5-2025-08-07")  // => "gpt-5"

// 3. 最新バージョンへのフィルタリング
filterToLatestVersions(["gpt-5", "gpt-5-2025-08-07", "gpt-5-2024-01-01"])
// => ["gpt-5", "gpt-5-2025-08-07"]
```

**実装**: `docker/services/ruby/public/js/monadic/model_utils.js`

## 表示ロジック

### Web UIモデルリスト生成

Web UIはプロバイダーのAPIが返すモデルに基づいて表示：

```
プロバイダーAPIの応答: ["gpt-5", "gpt-5-2025-08-07", "gpt-5-2024-01-01"]
                              ↓
                    filterToLatestVersions()
                              ↓
Web UIに表示:        ["gpt-5", "gpt-5-2025-08-07"]
```

### フィルタリングルール

各ベースモデル（例：`gpt-5`）について：

1. **日付付きバージョンなし**: 日付なしバージョンのみ表示
   - 入力: `["gpt-5"]`
   - 出力: `["gpt-5"]`

2. **日付付きバージョンのみ**: 最新の日付付きバージョンのみ表示
   - 入力: `["gpt-5-2024-01-01", "gpt-5-2025-08-07"]`
   - 出力: `["gpt-5-2025-08-07"]`

3. **日付なしと日付付き両方**: 日付なし + 最新の日付付きを表示
   - 入力: `["gpt-5", "gpt-5-2024-01-01", "gpt-5-2025-08-07"]`
   - 出力: `["gpt-5", "gpt-5-2025-08-07"]`

### 日付ソート

モデルは文字列比較ではなく実際の日付値でソート：

```javascript
// パースされた日付を使用した正しいソート
["command-r-08-2024", "command-r-03-2025", "command-r-12-2024"]
  => 最新: "command-r-03-2025" (2025年3月が最新)

// 文字列ソートでは誤って "command-r-12-2024" が選ばれる
```

## プロバイダー固有の動作

### OpenAIの例

**APIレスポンス**: `gpt-5`（日付なし）のみを返す

**model_spec.js**: `gpt-5`の仕様を含む

**Web UI**: `gpt-5`のみを表示

**直接使用**: MDSLで`gpt-5-2025-08-07`を指定可能、OpenAIは`gpt-5`として扱う

### Claudeの例

**APIレスポンス**: `claude-3-7-sonnet-20250219`（日付付きのみ）を返す

**model_spec.js**: `claude-3-7-sonnet-20250219`の仕様を含む

**Web UI**: `claude-3-7-sonnet-20250219`を表示

**注意**: Claudeモデルは通常、日付付きバージョンのみ

## 利点

### 重複の削減

変更前:
```javascript
"gpt-5": { /* 13個のプロパティ */ },
"gpt-5-2025-08-07": { /* 同じ13個のプロパティ */ }
```

変更後:
```javascript
"gpt-5": { /* 13個のプロパティ */ }
// gpt-5-2025-08-07は自動的にgpt-5に解決される
```

**結果**: `model_spec.js`のサイズが約13%削減

### 自動更新

プロバイダーが新しい日付バージョンを追加した場合：
- プロバイダーAPIが新バージョンを返す（例：`gpt-5-2025-12-01`）
- Web UIが自動的に`gpt-5`と並べて表示
- エイリアス解決により既存の`gpt-5`仕様を使用
- `model_spec.js`の手動更新は不要

### ユーザーの柔軟性

ユーザーは以下が可能：
- 安定したAPIのため日付なしバージョンを選択
- 最新機能のため最新の日付付きバージョンを選択
- MDSLで古い日付バージョンを指定（自動的にベース仕様にフォールバック）

## エッジケース

### 異なる仕様

日付付きと日付なしバージョンで仕様が異なる場合、両方を`model_spec.js`に保持：

```javascript
"gpt-4o": {
  "max_output_tokens": [1, 16384]
  // ...
},
"gpt-4o-2024-05-13": {
  "max_output_tokens": [1, 4096]  // 異なる！
  // ...
}
```

仕様が異なるため、両方がWeb UIに表示される。

### バージョン番号 vs. 日付

システムは正しく区別：

```
gpt-4.1              => 日付ではない（バージョン番号）
gemini-2.0-flash-001 => 日付（NNNフォーマット）
command-r7b-12-2024  => 7bは無視、12-2024は日付（MM-YYYYフォーマット）
```

## テスト

### Rubyテスト

```bash
cd docker/services/ruby
bundle exec ruby -e "
require_relative 'lib/monadic/utils/model_spec'

# 正規化のテスト
puts Monadic::Utils::ModelSpec.normalize_model_name('gpt-5-2025-08-07')
# => gpt-5

# エイリアス解決のテスト
puts Monadic::Utils::ModelSpec.resolve_model_alias('gpt-5-2025-08-07')
# => gpt-5
"
```

### JavaScriptテスト

```javascript
// 日付抽出のテスト
extractDateSuffix('magistral-small-2509')
// => { dateString: "2509", parsedDate: Date(2025-09-01), format: "YYMM" }

// フィルタリングのテスト
filterToLatestVersions(['gpt-5', 'gpt-5-2025-08-07', 'gpt-5-2024-01-01'])
// => ['gpt-5', 'gpt-5-2025-08-07']
```

## メンテナンス

### 新しい日付フォーマットの追加

1. JavaScriptの`extractDateSuffix()`にパターンマッチングを追加
2. `getBaseModelName()`のswitch文に対応するcaseを追加
3. Rubyの`normalize_model_name()`にパターンマッチングを追加
4. 代表的なモデル名でテスト

### model_spec.jsの更新

**日付付きバージョンを保持する場合**:
- 日付なしバージョンと仕様が異なる
- 日付付きバージョンのみ存在（日付なしが存在しない）

**日付付きバージョンを削除する場合**:
- 日付なしバージョンと仕様が完全に一致
- 日付なしバージョンがspecに存在

## 関連ファイル

- `docker/services/ruby/lib/monadic/utils/model_spec.rb` - Ruby正規化とエイリアス解決
- `docker/services/ruby/public/js/monadic/model_utils.js` - JavaScriptフィルタリングと日付解析
- `docker/services/ruby/public/js/monadic/model_spec.js` - モデル仕様
- `docker/services/ruby/lib/monadic/utils/provider_model_cache.rb` - フォールバック付きAPIモデル取得
- `docs_dev/developer/model_spec_vocabulary.md` - モデル機能の語彙（SSOT）
