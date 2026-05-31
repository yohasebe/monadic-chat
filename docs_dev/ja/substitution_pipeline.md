# Substitution Pipeline（置換パイプライン）

これは **Substitution Pipeline**（置換パイプライン）の設計と意思決定を記述する
内部開発者向けドキュメントである。ユーザーとアシスタントの境界でテキストを書き
換える2つの機能を、共通の仕組みの上に統合する。

- **Privacy Filter** — LLM に渡る前に PII をマスク（`<<PERSON_1>>`）し、応答で
  復元する。
- **Vocabulary** — ユーザーとアシスタントが `${TOKEN}` 変数（例: 共有データ
  フォルダを指す `${SHARED}`）を共有できるようにし、モデルが逐語的に知る必要の
  ない実パス/状態に解決する。

Privacy Filter のユーザー向け説明は `docs/advanced-topics/privacy-filter.md`。
Vocabulary はまだ公開ドキュメントを持たない（公開しているアプリが無いため。
「ステータス」参照）。

## なぜ1つの抽象に統合するか

両者は同じ発想の具体例である。すなわち、*記号* が共有の接点として機能すること
で、会話の双方は内的な「理解」が一致していなくても協調できる。PII マスキングと
共有パス変数は、同じ仕組み（入力時に書き換え、出力時に解決）に対する異なる
ポリシーにすぎない。1つの provider ベースのパイプラインに乗せることで、3つ目の
同種機能は「もう1つの provider」になり、ライフサイクル/順序の規則は一度書けば
よくなる。

## 用語

- **Pipeline**（`lib/monadic/substitution/pipeline.rb`,
  `Monadic::Substitution::Pipeline`）— provider の順序付きリストを保持し、各
  ライフサイクル段階で実行し、トークン解決チェーンを公開するオーケストレータ。
- **Provider**（`lib/monadic/substitution/provider.rb`）— 抽象基底。provider は
  ライフサイクルフックを override し、かつ/または所有する `${TOKEN}` 名を宣言
  する。
- **Context**（`lib/monadic/substitution/context.rb`）— session hash + アクティブ
  app をラップするメッセージ単位の読み取り面。
- **PrivacyFilter provider**
  （`lib/monadic/substitution/providers/privacy_filter.rb`）。
- **Vocabulary provider**
  （`lib/monadic/substitution/providers/vocabulary.rb`）+ built-in トークン
  レジストリ（`lib/monadic/substitution/vocabulary.rb`）。

## 2つのトークン名前空間（互いに素、概念上は共に `${...}`）

| 機能 | wire 形式 | 生成元 | 所有判定 |
|---|---|---|---|
| Privacy | `<<PERSON_1>>`, `<<EMAIL_ADDRESS_1>>` … | Python Presidio コンテナ（`docker/services/privacy/server.py`） | `<TYPE>_<N>` |
| Vocabulary | `${SHARED}` … | `Vocabulary::BUILTINS` で宣言 | 単一語 UPPER_CASE |

両者は衝突しない。Privacy の wire 形式は `${TYPE_N}` ではなく **`<<TYPE_N>>`** で
ある点に注意。検出と採番は Python 側で行われ、Ruby はその形式を consume して
round-trip するだけである（Privacy が `${...}` を使うという初期メモは誤り。
`${...}` は Vocabulary の構文）。

## ライフサイクルフック（Provider）

| 段階 | フック | Privacy | Vocabulary |
|---|---|---|---|
| user 入力 | `on_input(text, ctx)` | PII → `<<TYPE_N>>` | no-op（LLM は `${SHARED}` を見る必要がある） |
| system prompt | `system_prompt_addendum(ctx)` | — | 「## Shared variables」節 |
| tool 呼出 | `on_tool_invoke(name, args, ctx)` | no-op | `${SHARED}/x` → 実パスに展開（深く） |
| 出力描画 | `on_output_render(text, ctx)` | `<<TYPE_N>>` → PII 復元 | contract 用に保持。live 装飾は frontend へ移行（後述） |

加えて解決チェーン用の `owns_token?` / `resolve`、および `failure_mode`
（Privacy は `:closed` = 漏洩防止のため伝播必須、Vocabulary は `:open` = 失敗が
ターンを壊してはならない）。

## 確定した設計判断

| # | 判断 |
|---|---|
| A | *Vocabulary* は `${TOKEN}` 構文に統一（Privacy は legacy の `<<TYPE_N>>` wire 形式を維持）。 |
| B | バッククォートで escape: `` `${SHARED}` `` は展開せず literal。 |
| C | App ローカルスコープ: app 切替時にパイプラインを再構築。 |
| D | resolver lambda は **session hash** を引数に取る。 |
| E | 表示 resolver は既定で tool resolver。 |
| F | 失敗ポリシーは provider ごと（`failure_mode`）。 |

## Privacy: rewire でなく refactor

Privacy は **挙動を保ったまま**（Phase 2.2）`Substitution::Provider` に作り替えた。
live のホットパスは不変で、vendor adapter は従来通り `streaming_handler.rb` で
`apply_privacy_to_messages` / `before_send_to_llm`（マスク）と
`after_receive_from_llm`（復元）を呼ぶ。クラス自体が provider であり、
`Monadic::Utils::Privacy::Pipeline` として alias されるため、約21の duck-typed
呼び出し箇所はそのまま動く。

重要な不変条件: registry は `session[:monadic_state][:privacy]`（既存の
`Registry`）に置かれ、汎用の `Provider#state`（`session[:substitution_state]`）
には置かない —`Provider#state` は raise するよう override 済。これにより
`strip_for_persist`、言語検出の `[:detection]` サブ状態、privacy の export/import
経路が保たれる。

safety net: `spec/golden/privacy/` が Ruby 変換の挙動を format-neutral な golden
fixture として記録し、録画した Presidio 応答を stub で replay する（決定論的・
コンテナ不要）。詳細は `spec/golden/privacy/support.rb` のヘッダ参照。

## Vocabulary: parser → provider → live wiring → UI

1. **Parser**（Phase 3）— MDSL の `vocabulary do; use :shared; end`。
   `MonadicDSL::VocabularyConfiguration#use` は各名を
   `Monadic::Substitution::Vocabulary::BUILTINS` に対して検証し（typo は load 時に
   失敗）、plain data `{ tokens: [:shared] }` を生成する（dsl.rb の app クラス
   生成器が `.inspect` するため plain data 必須）。resolver は Ruby 側にあり、
   MDSL には置かない（MDSL は宣言的）。
2. **Provider**（Phase 4）— `Providers::Vocabulary.new(tokens:)`。`on_tool_invoke`
   は所有 `${TOKEN}`（および `${TOKEN}/sub/path` の接頭辞）を Hash/Array/String の
   引数全体に深く展開する。バッククォート内のトークンは literal のまま（判断 B）。
   `BUILTINS[:shared].resolve` は `->(session){ Environment.shared_volume }`。
3. **Live wiring**（Phase 5）— `base_vendor_helper.rb` に
   `substitution_pipeline_for`（opt-in、**Vocabulary 専用**パイプラインを
   `session[:_substitution_pipeline]` にキャッシュ）、
   `expand_tool_args_for_vocabulary`（8 vendor の `process_functions` に挿入。
   `:session` 注入の前に置き、session オブジェクトを walk しないようにする）、
   system-prompt addendum（8 vendor 編集でなく `SystemPromptInjector` の
   `SYSTEM_INJECTION_RULES` に `:vocabulary_variables` ルール1つ。`build_injections`
   が既に `APPS[app_name].settings` を解決しているため集約できる）を追加。
   `misc_handlers.rb` の app-change/reset で破棄。
4. **Token UI**（Phase 6）— 装飾を backend から frontend へ移行。backend は
   `vocabulary_map`（`{ "SHARED" => "/resolved/path" }`）をメッセージに添付
   （`privacy_known_entities` と同型）。`ws-vocabulary-handler.js` がレンダリング
   後の DOM を walk（LLM がパスを置く inline `<code>` 内も対象）し、`${TOKEN}` を
   クリック可能な `.vocab-token` span に包む。クリックで OS のファイルエクスプ
   ローラにパスを開く（`shell.openPath`/`showItemInFolder`、クロスプラット
   フォーム）。経路は既存の `webview-preload.js` → `ipcMain('reveal-path')`。
   browser モードは clipboard コピーに fallback。

### なぜ Vocabulary は専用パイプラインか（Privacy と共有しない）

Privacy は `:closed`、Vocabulary は `:open`。ライフサイクルは独立、名前空間は
互いに素。1つの `process_*` fold に同居させると2つの失敗 contract が絡む。
Privacy は実績ある legacy 経路に留め、`:_substitution_pipeline` には Vocabulary
のみを置く。

### dual-mode の reveal 変換

production では Ruby backend がコンテナ内で動くため `${SHARED}` はコンテナパス
`/monadic/data` に解決される —これは tool 展開には正しい（ツールはコンテナ内で
動く）。しかし OS のファイルエクスプローラはホストで動き、同じデータはホストの
`~/monadic/data` にある。修正は **出口** で行う: `app/main.js` の
`ipcMain('reveal-path')` が `/monadic/data` 接頭辞を
`path.join(os.homedir(),'monadic','data')` に変換する。resolver と ship される
map はコンテナ正のまま保つ。dev モードのパス（既にホストパス）は素通し。

## ファイルマップ

- `lib/monadic/substitution/{pipeline,provider,context,vocabulary}.rb`
- `lib/monadic/substitution/providers/{privacy_filter,vocabulary}.rb`
- `lib/monadic/utils/privacy/`（検出 backend アクセス、registry、types）
- `lib/monadic/dsl/configurations.rb`（`VocabularyConfiguration`）、`dsl.rb`（`vocabulary do`）
- `lib/monadic/adapters/base_vendor_helper.rb`（パイプライン構築 + tool-arg/装飾ヘルパ）
- `lib/monadic/utils/system_prompt_injector.rb`（`:vocabulary_variables` ルール）
- `lib/monadic/utils/websocket/{streaming_handler,html_handler,misc_handlers}.rb`
- `public/js/monadic/ws-vocabulary-handler.js`、`app/{webview-preload,main}.js`

## テスト

- `spec/unit/substitution/` — pipeline/provider/context の contract + 両 provider。
- `spec/golden/privacy/` — 挙動保存の golden fixture（+ `capture.rb --verify`）。
- `spec/unit/utils/privacy/` — 既存 199 privacy spec（不変）。
- `spec/unit/dsl/vocabulary_configuration_spec.rb`、`spec/unit/utils/system_prompt_injector_spec.rb`。
- `test/frontend/ws-vocabulary-handler.test.js`、`test/frontend/ws-privacy-handler.test.js`。

## ステータス

Live。`${SHARED}` は**全アプリで既定 ON**。このポリシーは
`Monadic::Substitution::Vocabulary.tokens_for(app_settings)`（パイプライン
ビルダーと system-prompt injector の双方が参照する単一の真実源）にある。アプリは
MDSL の `vocabulary false` で opt-out する。追加のための per-app opt-in は無く、
`vocabulary do … end` は将来のカスタムトークン用に予約。

`${SHARED}` は全アプリで **actionable** でもある: `MonadicDSL.inject_file_operations!`
（dsl.rb、`inject_library_search!` を踏襲）が全アプリに共有フォルダの
`read/write/list` ツールを既定付与する（除外なし）。帰結として、orchestration
モデルは tool-capable が前提 — 非 tool-capable モデルにはそもそもツールが送られない
（vendor helper が `tool_capability` で gate）ため、既存の「tool calling 前提」方針と
整合。ユーザー向け公開ドキュメント（`docs/`, `docs/ja/`）が残りのフォローアップ。
