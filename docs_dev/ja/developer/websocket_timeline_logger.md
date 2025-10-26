タイトル: 初期化トレーシング用WebSocketタイムラインロガー

概要
- 初期化とメッセージ処理順序をトレースするための小さなタイムラインロガーがブラウザで利用可能です。

使用方法
- ロガーは`window.logTL(event, payload)`として公開されています。
- `[TL] <event>`としてコンソールに簡潔なエントリを書き込み、後の検査のために`window._timeline`にも記録します。

一般的なイベント
- `apps_received`：APPSメッセージが到着、カウンターと現在の選択を含む。
- `parameters_received`：PARAMETERSメッセージが到着、`app_name`/`model`フラグを含む。
- `proceedWithAppChange_called_from_apps`：初回ロード時に自動選択パスが呼び出される。
- `loadParams_called_from_proceed`：アプリ変更後にパラメーターロードが実行される。

確認場所
- `docker/services/ruby/public/js/monadic/websocket.js`で定義されています。

ノート
- ロガーは意図的に軽量で、副作用はありません。デバッグビルドで有効にしても安全なまま維持する必要があります。
