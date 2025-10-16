# 「#model-selected」同期不具合 改善提案（実装案）

最終更新: 2025-09-05

## 背景 / 症状
- アプリ切替時（`loadParams(params, "changeApp")` 経由）にモデルが変更されても、メニューパネルの `#model-selected` が最新のモデル・reasoning設定を反映しないことがある。
- Claude案では `changeApp` ブランチで `setTimeout(() => $("#model").trigger('change'), 50);` を入れる提案だが、`loadParams` 内での推論UI（ReasoningMapper/Labels）の更新タイミングと競合し、不完全な表示になるリスクが残る。

## 原因の考察
- `loadParams` の中で UI が段階的に更新される（モデル選択→推論UI構築→ラベル/値の確定）。
- 早すぎる `$('#model').trigger('change')` は、`#reasoning-effort` がまだ未設定の段階で `#model-selected` を描画し、整合が崩れる。

## 解決方針（2案）

### 案A（推奨・より堅牢）: バッジ更新ヘルパーの導入
- 小さな共通関数 `updateModelSelectedBadge()` を作成し、以下の2か所から呼び出す。
  1) `monadic.js` 内の `#model change` ハンドラ
  2) `utilities.js` の `loadParams()` 終端（全UI更新が完了した直後）
- 重複している文字列組み立てロジック（provider推定、reasoning有無の分岐）をこの関数に集約してドリフトを防ぐ。

疑似コード（新規ヘルパー）:
```js
function updateModelSelectedBadge() {
  const model = $("#model").val();
  if (!model) return;

  // アプリの group から provider 名推定
  let provider = "OpenAI";
  const currentApp = $("#apps").val();
  if (apps[currentApp] && apps[currentApp].group) {
    const group = apps[currentApp].group.toLowerCase();
    if (group.includes("anthropic") || group.includes("claude")) provider = "Anthropic";
    else if (group.includes("gemini") || group.includes("google")) provider = "Google";
    else if (group.includes("cohere")) provider = "Cohere";
    else if (group.includes("mistral") || group.includes("pixtral") || group.includes("ministral") || group.includes("magistral") || group.includes("mixtral") || group.includes("devstral") || group.includes("voxtral")) provider = "Mistral";
    else if (group.includes("perplexity")) provider = "Perplexity";
    else if (group.includes("deepseek")) provider = "DeepSeek";
    else if (group.includes("grok") || group.includes("xai")) provider = "xAI";
  }

  // reasoning対応モデルなら #reasoning-effort の値を併記
  const hasReasoning = window.modelSpec && window.modelSpec[model] && Object.prototype.hasOwnProperty.call(window.modelSpec[model], "reasoning_effort");
  if (hasReasoning) {
    const effort = $("#reasoning-effort").val() || "minimal";
    $("#model-selected").text(`${provider} (${model} - ${effort})`);
  } else {
    $("#model-selected").text(`${provider} (${model})`);
  }
}
```

差分ポイント:
- `monadic.js` の `$("#model").on("change", ...)` 内の文字列組み立てを `updateModelSelectedBadge()` 呼び出しに置換。
- `utilities.js` の `loadParams()` の末尾（推論UIや各値設定が終わった後）に `setTimeout(updateModelSelectedBadge, 0);` を1回だけ追加。
- `changeApp` ブランチでは **trigger しない**（早すぎるため）。

メリット:
- タイミング競合を回避（最終段で1回だけ更新）。
- 表示ロジックの一元化で保守性向上。
- 既存の `#model change` ハンドラも自然に機能継続。

### 案B（差分最小・十分安全）: loadParams 終端で一度だけ change を発火
- `loadParams()` の **末尾** に `setTimeout(() => $("#model").trigger('change'), 0);` を追加するのみ。
- `changeApp` ブランチ内では発火しない。

メリット:
- 既存の `#model change` ハンドラをそのまま活用できる。
- 末尾発火のため、推論UIやラベルの更新後に実行され、整合性が取りやすい。

デメリット:
- `#model change` ハンドラの組み立てロジックが将来変更された場合、`#model-selected` のフォーマットもそちら依存で追従（案Aほど明示的ではない）。

## 実装範囲（想定）
- 変更ファイル:
  - `docker/services/ruby/public/js/monadic.js`
  - `docker/services/ruby/public/js/monadic/utilities.js`
- 差分規模: 小（数十行以内）
- 既存API・サーバ側変更: 不要

## テスト観点
- アプリ切替（reasoningあり/なし）で `#model-selected` が即時に正しく更新される
- モデルのみ変更（アプリ不変）でも従来通り更新される
- 推論ドロップダウンの値を変更した場合、`#model-selected` に反映される
- カスタムドロップダウン（`#app-select-icon`）のアイコン更新に副作用がない
- コンソールエラーが発生しない

## ロールバック計画
- 既存の `#model change` ハンドラロジックは保持するため、案Bは末尾の1行（setTimeout）を削除するのみで戻せる。
- 案Aはヘルパー導入だが、置換前の文字列生成を戻すだけで復旧可能。

## 推奨
- 本番安定性を優先: まずは **案B**（末尾trigger）で最小差分導入 → 挙動確認 → 問題なければ維持。
- 長期の保守性: 将来的に **案A**（ヘルパー集約）へ移行し、表示ロジックの重複とドリフトを解消。

## 備考
- `updateAppSelectIcon()` は `monadic.js` 側で `loadParams("changeApp")` 後に既に呼ばれているため、`utilities.js` 側で重複呼び出しはしない方が安全（描画の二重適用を避ける）。
