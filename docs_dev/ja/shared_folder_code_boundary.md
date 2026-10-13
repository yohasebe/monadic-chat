# 共有フォルダとサーバーのコード

共有フォルダ（`~/monadic/data`、コンテナ内では `/monadic/data`）には、コンテナでコードを実行するツールが書き込みます。そこにあるファイルはデータであり、サーバーがそこからコードを実行・読み込むのは、下の規則を通したときだけです。ツール、ルート、コンテナを足すときは、この規則を守ってください。

## サーバーが実行・読み込むもの

- **Ruby 側のコマンド**（`send_command(container: "ruby")`）：Monadic Chat に付属するスクリプトだけを、`RbConfig.ruby` と絶対パスで実行します。付属でない Ruby スクリプトは拒否します。PATH には、付属のスクリプトのフォルダと、共有フォルダを除いたサーバー自身の PATH を置きます。コマンドの環境からは認証情報を外し、付属のスクリプトは設定から鍵を読みます（`SecretReferences.config_value`）。共有フォルダの `scripts` の利用者スクリプトは、Python コンテナでだけ実行されます。
- **自作のアプリとヘルパー**（`apps/`・`helpers/`）：`SharedPathGuard.user_code_files`（`code_files` と `code_file?` を使う）を通してだけ読み込みます。リンクのフォルダ、リンクのファイル、別のハードリンクがあるファイル、フォルダの外にあるファイルは読みません。DSL のローダーは、アプリの `_constants.rb`・`_tools.rb` も同じ規則で読み込みます。
- **コンテナの定義**（`services/`・`apps/*/services/`）：`monadic.sh` は、その `compose.yml` を `docker compose` の実行に含め、「Build User Containers」でビルドします。生成する compose のファイルは `~/monadic/config` に書き、共有フォルダには書きません。
- **Electron アプリが共有フォルダで読み書きするもの**（ドキュメント DB の書き出しと取り込み）：`app/no_follow_files.js` を通します。書き込みは `~/monadic/.staging` で行い、書き終えてから名前を付け替えて置きます。読み込みは、確かめた通常のファイルだけを開きます。アプリが開くのは共有フォルダそのものだけで、ほかの項目はファイルマネージャーで選択して表示します。
- **Python コンテナの PATH：** 利用者の `scripts/` は、システムのフォルダより後ろに置きます。

## 規則を保つ場所

- **マウント：** `apps/`・`helpers/`・`services/` は、共有フォルダをマウントするすべてのコンテナ（Python・Selenium・Extractor・Ruby）で読み取り専用です。`monadic.sh`（`ensure_code_dirs`）は、どのコンテナよりも先にこれらを利用者の権限で作り、作れないときやリンクのときは起動しません（コンテナを下ろす操作は動きます）。`test/electron/code-dirs-mount.test.js` が、CI の Linux で実際のコンテナを使ってマウントを確かめます。
- **サーバーの書き込み：** ファイル名をモデルやページが決める書き込み（ファイルのツール、アップロード、Web 検索の保存、プロバイダが送るファイル、アプリのテンプレート、AutoForge のプロジェクトのファイル）は `SharedPathGuard.write_file!` を通します。`apps`・`helpers`・`scripts`・`services` と、書く場所のリンクを拒否します。
- **試験：** ツールに共有フォルダへ書かせる spec は、`Monadic::Utils::Environment.shared_volume` と `data_path` を一時フォルダに向けます。利用者の共有フォルダが要る spec（動いているコンテナがそこを読む）は、置いたものを後で消します。

## 開発モード

`rake server:debug` ではサーバーがホストで動き、シェルで `MONADIC_LOAD_USER_CODE=true` を付けて起動しない限り、共有フォルダの自作アプリとヘルパーを読み込みません。

```bash
MONADIC_LOAD_USER_CODE=true rake server:debug
```

有効にできるのはシェルだけです。`rake server:debug` は、この設定がシェルにあったときだけサーバーへ渡し、サーバーは `~/monadic/config/env` にこの名前があれば無視します。無効のときにフォルダにファイルがあれば、起動時に一度だけ知らせます。自作アプリを作っている間だけ付けてください。
