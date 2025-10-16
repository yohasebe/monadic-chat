# ロギング（場所、種類、追加ログ）

Monadic Chatは、ホスト上の`~/monadic/log`にログを書き込みます。コンソールパネル（メニュー → 開く → ログフォルダを開く）から、このディレクトリに移動できます。

一般的なファイル：
- `server.log` — RubyウェブアプリのThinサーバーログ
- `docker-build.log`、`docker-startup.log` — dockerライフサイクルログ
- `command.log` — シェル/コード実行トレース
- `jupyter.log` — Jupyterセル追加/実行ログ
- `extra.log` — 詳細検査用の冗長な構造化ストリーム（下記参照）

注意事項：
- 起動時、アプリはRuby control-planeのヘルスをプローブします。コンテナが明示的に異常で、自動リフレッシュが有効な場合のみ、Rubyを1回再ビルドして再試行します。この場合、`docker_startup.log`には以下が含まれます：
  - `Auto-rebuilt Ruby due to failed health probe`

## ビルドログ

- Pythonビルド（実行ごとに上書き）：
  - `~/monadic/log/docker_build_python.log`：Dockerビルドのstdout/stderr（検証済みプロモーションフローを含む）
  - `~/monadic/log/post_install_python.log`：`~/monadic/config/pysetup.sh`が存在する場合の実行出力（オプション）
  - `~/monadic/log/python_health.json`：ビルド直後のヘルスチェック結果（LaTeX/convert/Pythonライブラリ）
  - `~/monadic/log/python_meta.json`：実行メタデータ（Monadicバージョン、ホストOS、ビルド引数など）
- Ruby/User/Ollamaビルド（実行ごとに上書き）：
  - `~/monadic/log/docker_build.log`

ビルドの進行状況とログはメインコンソールに表示されます。インストールオプションウィンドウは自動的に再ビルドをトリガーせず、ビルド出力をストリーミングしません。

レンダラーメッセージルーティング：
- `[HTML]:`（または構造化エラータグ）として明示的にタグ付けされたサーバー送信メッセージのみが`#messages`ペインにレンダリングされます。
- プレーンなコマンド出力は常に`#output`ログエリアに残ります。

## オーケストレーションヘルスプローブ（起動時）

- Startコマンドは、Ruby control-planeがサービスを調整する準備ができていることを確認します。`~/monadic/config/env`でプローブを調整できます：

```
START_HEALTH_TRIES=20
START_HEALTH_INTERVAL=2
```

- 自動リフレッシュトグル（オプション）：

```
# falseに設定すると、ヘルス失敗時でもアプリはRubyを自動的に再ビルドしません
AUTO_REFRESH_RUBY_ON_HEALTH_FAIL=true
```

- 動作の概要：
  - Healthy：続行。
  - Starting/Unknown：`START_HEALTH_*`まで待機を継続（再ビルドなし）。
  - Unhealthy：`AUTO_REFRESH_RUBY_ON_HEALTH_FAIL=true`の場合、Rubyを1回再ビルドして再試行。

## ビルド同時実行ガード

- すべてのビルドコマンドは、`~/monadic/log/build.lock.d`の軽量ロックでシリアル化されます。
- ビルドが既に実行中の場合、UIは情報メッセージを表示し、すぐに戻ります。

## 追加ログ

- 設定 → システム → 「追加ログ」で切り替え可能。
- `rake server:debug`で強制的に有効化（Rakefileが`EXTRA_LOGGING=true`を設定）。
- ファイルパスは一元化：`MonadicApp::EXTRA_LOG_FILE`（`Monadic::Utils::Environment.extra_log_file`経由）。
- 多くのアダプター/ヘルパーは、ここに構造化イベントを追加します（例：プロバイダーリクエスト/レスポンス、ツール呼び出し）。

### ログローテーション

- 無制限の増加を防ぐため、一部のログは`LOG_ROTATE_MAX_BYTES`（デフォルト5MB）を超えるとサイズでローテーションします。
- ローテーションは最大`LOG_ROTATE_MAX_FILES`（デフォルト5）世代を保持：`log`、`log.1`、`log.2`、...
- 現在適用されているもの：
  - `~/monadic/log/command.log`
  - `~/monadic/log/jupyter.log`
- `~/monadic/config/env`で設定：

```
LOG_ROTATE_MAX_BYTES=10485760   # 10MB
LOG_ROTATE_MAX_FILES=7          # 7世代を保持
```

## テスト実行アーティファクト

- ランタイムログとは独立して、RSpec実行は`./tmp/test_runs/<timestamp>/`に書き込みます：
  - `summary_compact.md`、`summary_full.md`、`rspec_report.json`、`env_meta.json`。
  - 最新シンボリックリンク：`./tmp/test_runs/latest`。
- 古い実行ディレクトリは自動的にプルーニングされ、最新の結果のみが残ります。履歴アーティファクトを保持する必要がある場合は、スイートを実行する前に`SUMMARY_PRESERVE_HISTORY=true`（または`SUMMARY_KEEP_HISTORY=true`）を設定してください。

## ヒント

- APIレベルの診断には、テスト環境で`EXTRA_LOGGING=true`と`API_LOG=true`を組み合わせます。
- Electronパスの問題を調査する場合、`app/main.js`に一時的な`console.log`を追加してDevToolsで確認します。
- Pythonコンテナのビルドが失敗した場合、最新の実行ごとのディレクトリで`docker_build.log`と`post_install.log`を確認してください。

## レンダラーメッセージルーティングガイドライン（開発者向け）

Electronレンダラーには2つのペインがあります：`#messages`（HTML、ユーザー向けステータス）と`#output`（プレーンコンソールログ）。UIを予測可能でノイズのないものに保つため、メインプロセスやサーバーからメッセージを発行する際は以下のルールに従ってください：

- `#messages`に送るもの：
  - `[HTML]:`またはエラーマーカー（例：`[ERROR]:`）で明示的にタグ付けされたコンテンツのみが`#messages`にレンダリングされます。
  - 既存のヘルパー（Electron `formatMessage(type, key, params)`またはサーバー側HTMLスニペット）を使用して、適切に構造化され、ローカライズされたHTML行を生成します。
  - 許可されたセマンティックタイプとアイコン/色（一貫性を保つ）：
    - info：circle-info、`#61b0ff`
    - success：circle-check、`#22ad50`
    - warning：circle-exclamation、`#FF7F07`
    - error：circle-exclamation、`#DC4C64`

- `#output`に送るもの：
  - すべてのプレーンテキストログとコマンド出力（Docker、ビルドステップ、スクリプトのstdout/stderr）は、タグなし（`[HTML]:`なし）のままにする必要があります。
  - 長いストリーミング出力はHTMLとしてラップしないでください。

- フォールバックに依存しない：
  - レンダラーはもはやプレーン行を`#messages`に昇格させません。ユーザー向けのステータス行を意図する場合は、`[HTML]:`を送信する必要があります。
  - HTMLと同じテキストをプレーン出力として両方を発行しないでください。`#messages`の短いHTML要約 + `#output`の詳細ログを優先してください。

- 国際化（i18n）：
  - 翻訳されたメッセージには、Electronメインプロセスで`formatMessage()`を使用することを優先（言語変更時の再翻訳用のデータ属性を含む）。
  - サーバー側のHTMLスニペットには、翻訳が利用できない場合は中立的な英語を使用し、短く情報的に保ちます。

- 例（Electronメイン）：
  - Info：`[HTML]: <p><i class='fa-solid fa-circle-info' style='color:#61b0ff;'></i> Checking orchestration health . . .</p>`
  - Success：`formatMessage('success', 'messages.buildPythonFinished')`を使用
  - Error：`[ERROR]: Something bad happened`（レンダラーはエラースタイルで`#messages`にレンダリング）

- アンチパターン（回避）：
  - 大きなコマンド出力を`[HTML]:`として発行（`#messages`を汚染） — `#output`に保つ。
  - タグなしのプレーン情報を発行して`#messages`に表示されることを期待 — されません。
  - 上記で確立されたアイコン色と矛盾するインラインスタイリング。

これらのルールに従うことで、ユーザーは`#messages`で簡潔でローカライズされたステータスを見ることができ、完全な技術的出力は`#output`でアクセス可能なままになります。
