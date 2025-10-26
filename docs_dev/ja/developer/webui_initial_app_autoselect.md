タイトル: Web UI初期アプリ自動選択とプロンプト初期化

概要
- Web UIは、初回ロード時に利用可能な最初のアプリを確実に初期化し、手動で再選択することなく初期プロンプトを挿入するようになりました。

変更内容
- APPSが受信されるとすぐに完全なappsペイロードをグローバル`apps`マップにキャッシュし、`proceedWithAppChange(firstValidApp)`が`system_prompt`に即座にアクセスできるようにします。
- 最初のAPPSレンダリング時に、有効な選択が存在するが初期化がまだ実行されていない場合、パラメーターが入力され初期プロンプトが挿入されることを確実にするために、`proceedWithAppChange`を一度呼び出します。
- デバッグ中にAPPS/PARAMETERS/初期化順序をトレースするのに役立つ軽量タイムラインロガー`window.logTL(event, payload)`を追加しました。

確認場所
- 初期化：`docker/services/ruby/public/js/monadic/websocket.js`
- アプリ変更：`docker/services/ruby/public/js/monadic.js`
- パラメーターロード：`docker/services/ruby/public/js/monadic/utilities.js`

デバッグヒント
- DevToolsコンソールを開いて`[TL]`エントリを探します：
  - `apps_received`、`proceedWithAppChange_called_from_apps`、`loadParams_called_from_proceed`など。
  - これらのイベントは順序を確認するのに役立ちます：APPS → proceedWithAppChange → loadParams → プロンプト挿入。

ノート
- このロジックはユーザー選択の動作を変更しません；手動入力なしで初回実行の初期化が完了することを保証するのみです。
