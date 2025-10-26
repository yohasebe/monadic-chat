# Web UIアプリセレクターとインポートの注意点、SSOT方針（開発者向け）

最終更新: 2025-09-05

## アプリセレクター（Web UI）の仕様
- カスタムメニュー（オーバーレイ）: `#apps` セレクトの上に独自ドロップダウン（`#custom-apps-dropdown`）とオーバーレイ（`#app-select-overlay`）を重ねて表示・操作しています。
  - `#apps` の値を真とし、カスタムメニューはそれに追従（ハイライト・グループ展開など）します。
  - アイコン表示は `updateAppSelectIcon(appValue)` が担当。`apps[appValue].icon` → 取れない場合はカスタムメニューからフェイルセーフ取得 → さらに汎用アイコンでフォールバック。
- 初期状態: WebSocketの APPS_LIST 受信後に候補を構築します。
  - 既定の自動選択（OpenAI/Chat優先）ロジックはありますが、「インポート中」またはすでに有効な選択がある場合はスキップするようガード済みです。

## インポート処理の注意点（UIとの関わり）
- インポートは app_name → model の順で UI に反映します。
  - `updateAppAndModelSelection(parameters)` で `#apps` と `#model` を順にセットし、それぞれ `change` を発火します。
  - その直後に proceedWithAppChange が並行して走る場合に上書きされないよう、インポート期間を示すフラグ（`window.isImporting`）と時刻（`window.lastImportTime`）でガードしています。
  - APPS_LIST 側の「既定アプリの自動選択」は、`isImporting` または「すでに有効な選択値がある」場合にスキップします。
- 競合回避の要点:
  - インポート中は `isImporting = true` を先頭で立て、app/model 適用が終わってから十分な猶予（~500ms）で false に戻します。
  - 直近1秒以内のインポート（`lastImportTime`）も自動選択を抑止します（遅延レース対策）。
- よくある落とし穴:
  - アプリの provider/group を params で持ち回ると、次のアプリ切替時に誤ったラベル・メニューが表示されることがあります。通常フローでは `apps[appValue].group` を正として params.group を同期し、apps 定義自体は決して上書きしません（インポート時のみ必要であれば限定的に対応）。

## ヘルパーファイルにおけるSSOT方針
- SSOT（model_spec.js）を一次情報源とします。機能判定は可能な限り spec から参照し、未定義時のみ旧ロジックにフォールバックします。
  - 代表例: `tool_capability`, `supports_streaming`, `vision_capability`, `supports_pdf`, `supports_web_search`, `reasoning_effort`, `supports_thinking`, `supports_verbosity`, `latency_tier`, `beta_flags` など。
- フォールバック戦略（推奨）:
  1) spec に定義があればそれを使用
  2) プロバイダ既定（安全に保てる既定値）
  3) それでも不明な場合は安全側（無効化）
- 導入順序（小さく安全に）:
  - Phase 0: 観測・棚卸し（分岐の語彙化）
  - Phase 1: spec-first（例: tool_capability / supports_streaming）＋未定義フォールバック
  - Phase 2: 正規化レイヤ導入（メッセージshape/パラメータ共通化）
  - Phase 3: 旧ハードコードの撤廃（specカバレッジが揃い次第）
  - Phase 4: spec駆動の契約テスト
- ロギング/監視:
  - EXTRA_LOGGING 時には「適用した能力」「無効化したパラメータ」「選択エンドポイント」「出所（spec/既定/フォールバック）」を簡潔に記録できるようにしておくと移行が安全です。

---
このドキュメントは、UIとインポートの相互作用、およびヘルパーのSSOT方針を短く実務的にまとめたものです。実装フロー中に競合や差し戻しが必要になった場合は、ここを起点に原因と対策を確認してください。
