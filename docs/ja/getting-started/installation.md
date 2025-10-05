# インストール

## 基本的な手順 :id=basic-steps

<!-- tabs:start -->

### **macOS**

macOSの場合、以下の手順でMonadic Chatをインストールします。

1. Docker Desktop for Macをインストールします。
2. Monadic Chatのインストーラーをダウンロードしてインストールします：

- 📦 [macOS用の最新リリースをダウンロード](https://github.com/yohasebe/monadic-chat/releases/latest)


### **Windows**

Windowsの場合、以下の手順でMonadic Chatをインストールします。

1. WSL2をインストールします。
2. Docker Desktop for Windowsをインストールします。
3. Monadic Chatのインストーラーをダウンロードしてインストールします：

- 📦 [Windows用の最新リリースをダウンロード](https://github.com/yohasebe/monadic-chat/releases/latest)


### **Linux**

Linux（Ubuntu/Debian）の場合、以下の手順でMonadic Chatをインストールします。

1. Docker Desktop for Linuxをインストールします。

参照：[Install Docker Desktop on Linux](https://docs.docker.jp/desktop/install/linux-install.html)

2. Monadic Chatのインストーラーをダウンロードします：

- 📦 [Linux用の最新リリースをダウンロード](https://github.com/yohasebe/monadic-chat/releases/latest)


3. ターミナルで以下のコマンドを実行してダウンロードしたパッケージをインストールします：

```shell
$ sudo apt install ./monadic-chat-*.deb
```

<!-- tabs:end -->

## 初期設定 :id=initial-setup

インストール後、Monadic Chatを初めて起動すると：

1. アプリケーションが自動的にDockerコンテナのビルドを開始します
2. **初回セットアップ時間**: このプロセスはかなりの時間がかかる場合があります（インターネット接続とシステム性能に大きく依存）。初回ビルドでは約12GBの複数のコンテナをダウンロード・構築します。
3. **以降の起動**: 初回ビルド後は、既存のコンテナが再利用されるため、Monadic Chatの起動は格段に速くなります。コンテナの再ビルドは、Monadic Chatの新しいバージョンに更新する時のみ必要です。
4. 使用したいAIサービスのAPIキーを設定パネルで設定する必要があります
5. コンテナの準備が完了すると、ステータスインジケータが緑色になります

詳細な設定手順については、[Webインターフェース](../basic-usage/web-interface.md)セクションを参照してください。

## インストールオプションと再ビルド :id=install-options

アプリのメニュー「アクション → インストールオプション…」から、Python コンテナに含めるオプションを選べます。

- LaTeX（最小構成）: Concept Visualizer / Syntax Tree の有効化（OpenAI/Anthropic のキーが必要）
- Python ライブラリ（CPU）: `nltk` / `spacy(3.7.5)` / `scikit-learn` / `gensim` / `librosa` / `transformers`
- Tools: ImageMagick（`convert`/`mogrify`）

パネルの仕様:
- インストールオプションウィンドウはモーダルで、Settingsパネルと同サイズです。
- Save（保存）してもウィンドウは閉じません。保存成功は緑色のチェックで短く通知します。
- 未保存の変更がある状態で Close を押すと、確認ダイアログ（「保存して閉じる／キャンセル」）が表示されます。
- タイトル／説明／ボタン／ダイアログはUI言語（英/日/中/韓/西/独/仏）に追従します。

保存しても自動で再ビルドは行いません。準備ができたらメインコンソールから Rebuild を実行してください。再ビルドは一時タグでビルド→ヘルス確認→成功時のみ本番へ反映というアトミック更新で、進捗はメインコンソールに出力されます。完了後の要約やヘルスチェックはログと同じ場所に保存されます。

Start 時の挙動: Start を押すとオーケストレーションのヘルスチェックを行い、必要であれば Ruby（制御プレーン）を一度だけ自動リフレッシュして起動を続けます。メッセージは「情報」トーンで表示され、最終的に緑色の成功表示で準備完了が示されます。

プローブ調整（任意）: `~/monadic/config/env`

```
START_HEALTH_TRIES=20
START_HEALTH_INTERVAL=2
```

依存指紋ベースの Ruby 再ビルド
- Ruby は **Gem 依存が変わったときにのみ** 再ビルドされます。`Gemfile` と `monadic.gemspec` の SHA256 を画像ラベル `com.monadic.gems_hash` に保持し、作業コピーと異なる場合にだけ更新します。通常は bundle レイヤーがキャッシュ再利用されます。
- トラブルシューティングで完全ノーキャッシュで再構築したい場合は、以下を設定してください：

```
FORCE_RUBY_REBUILD_NO_CACHE=true
```

ログ保存先（実行ごとに上書き）:

- Python ビルド: `~/monadic/log/docker_build_python.log`, `~/monadic/log/post_install_python.log`, `~/monadic/log/python_health.json`, `~/monadic/log/python_meta.json`
- Ruby / User / Ollama ビルド: `~/monadic/log/docker_build.log`

NLTK と spaCy の挙動

- `nltk` を有効にしてもライブラリのみインストール（データ/コーパスの自動ダウンロードは行いません）。
- `spacy` を有効にしても `spacy==3.7.5` のみインストール（言語モデルの自動ダウンロードは行いません）。
- 推奨: `~/monadic/config/pysetup.sh` にダウンロード処理を記述し、ポストセットアップで取得します。例:

```sh
#!/usr/bin/env bash
set -euo pipefail

python - <<'PY'
import nltk
for pkg in ["punkt","stopwords","averaged_perceptron_tagger","wordnet","omw-1.4","vader_lexicon"]:
    nltk.download(pkg, raise_on_error=True)
PY

python -m spacy download en_core_web_sm
python -m spacy download en_core_web_lg
```

日本語モデルと追加コーパスの例

```sh
#!/usr/bin/env bash
set -euo pipefail

# spaCy 日本語モデル（いずれか）
python -m spacy download ja_core_news_sm
# もしくは: ja_core_news_md / ja_core_news_lg

# NLTK 追加コーパス（例でよく使うもの）
python - <<'PY'
import nltk
for pkg in ["brown","reuters","movie_reviews","conll2000","wordnet_ic"]:
    nltk.download(pkg, raise_on_error=True)
PY
```

NLTKをすべてダウンロードする場合（フル）

```sh
#!/usr/bin/env bash
set -euo pipefail

export NLTK_DATA=/monadic/data/nltk_data
mkdir -p "$NLTK_DATA"

python - <<'PY'
import nltk, os
nltk.download('all', download_dir=os.environ.get('NLTK_DATA','/monadic/data/nltk_data'))
PY
```
※ 数GB規模で時間がかかります。十分な空き容量をご確認ください。

## 準備 :id=preparation

### システム要件 :id=system-requirements

- **Docker Desktop**: バージョン4.20以降（4.20+でテスト済み；それより古いバージョンでも動作する可能性はありますが保証されません）
- **メモリ**: 最低8GB RAM（最適なパフォーマンスには16GB推奨）
- **ストレージ**: 最低15GBの空き容量（Dockerイメージに約12GB、ユーザーデータとログに追加容量）

<!-- tabs:start -->

### **macOS**

macOSの場合、Docker Desktopをインストールするために以下の手順に従ってください。Docker Desktopはコンテナを使用して仮想環境を作成するソフトウェアです。

MacのCPUによって異なるパッケージを使用します。CPUの種類は、ターミナルで以下のコマンドで確認できます。

```shell
$ sysctl -n machdep.cpu.brand_string
```

[Docker Desktop](https://docs.docker.com/desktop/)からDocker Desktopをダウンロードしてインストールします。Intelの場合は`Docker Desktop Installer.dmg`を、Apple Siliconの場合は`Docker Desktop Installer Apple Silicon.dmg`をダウンロードします。

![](../assets/images/mac-docker-download.png ':size=800')

ダウンロードしたdmgファイルをダブルクリックしてウィンドウを表示し、Dockerアイコンをアプリケーションフォルダにドラッグします。インストールが完了したら、Docker Desktopを起動します。サービス契約に同意するかどうか（同意する）、推奨設定を使用するかどうか（特別な好みがない限り、推奨設定を使用する）、osascriptの内部使用のためにMacのユーザー名とパスワードを入力するよう求められます。

Docker Desktopが起動すると、タスクバーにDockerアイコンが表示されます。この時点でDocker Desktopのダッシュボードウィンドウを閉じることができます。

### **Windows**

Windows 11でMonadic Chatを使用するには、Windows Subsystem for Linux 2（WSL2）とDocker Desktopをインストールする必要があります。以下はWindows 11 HomeにMonadic Chatをインストールする方法です。同じ方法をWindows 11 ProやWindows 11 Educationでも使用できます。

#### WSL2のインストール

まず、[WSL2](https://docs.microsoft.com/ja-jp/windows/wsl/install)をインストールします。これはWindows上でLinux環境を実現するメカニズムです。

管理者モードでPowerShellを開きます。Windowsの検索ボックスでPowerShellを検索し、「管理者として実行する」を選択してpowershell.exeを起動します。

![](../assets/images/win-powershell.png ':size=800')

次に、PowerShellで以下のコマンドを実行します（先頭の`>`はコマンドラインプロンプトを表します）。

```shell
> wsl --install -d Ubuntu 
```

![](../assets/images/win-wsl-install.png ':size=800')

その後、コンピュータを再起動します。再起動後、WSL2とUbuntuがインストールされます。このプロセスでは、Linux環境のユーザー名とパスワードを入力するよう求められます。任意のユーザー名とパスワードを入力してください。このユーザー名とパスワードは後で使用するために覚えておく必要があります。

これでWSL2のインストールは完了です。UbuntuがWindowsで利用可能になりました。Windowsの検索ボックスで「Ubuntu」を検索し、Ubuntuターミナルを開きます。

![](../assets/images/win-ubuntu.png ':size=800')

#### Docker Desktopのインストール

次に、コンテナを使用して仮想環境を作成するソフトウェアであるDocker Desktopをインストールします。

[Docker Desktop](https://docs.docker.com/desktop/)からDocker Desktopをダウンロードします。

![](../assets/images/win-docker-download.png ':size=800')

ダウンロードしたexeファイルをダブルクリックしてインストールを開始します。インストールが完了したら、Docker Desktopを起動します。Docker Desktopを初めて起動すると、サービス契約に同意する（同意する）かどうかと、設定を選択する（推奨設定を使用する）かどうかを尋ねられます。

これらが完了すると、Docker Desktopアイコンが画面右下のタスクトレイに表示されます。Docker Desktopが起動すると、Docker Desktopダッシュボードウィンドウを閉じることができます。

### **Linux**

Linux（Ubuntu/Debian）の場合、Docker Desktopをインストールするには以下のページを参照してください。

- [For Debian](https://docs.docker.jp/desktop/install/debian.html)
- [For Ubuntu](https://docs.docker.jp/desktop/install/ubuntu.html)

<!-- tabs:end -->

## サーバーモードの設定 :id=server-mode-configuration

**注意：Monadic Chatは主にスタンドアロンモード（すべてのコンポーネントが単一のマシン上で動作）での使用を想定して設計されています。サーバーモードは、ローカルネットワーク上で複数のユーザーとサービスを共有する必要がある場合にのみ使用してください。**

デフォルトでは、Monadic Chatは単一のマシン上ですべてのコンポーネントを実行するスタンドアロンモードで動作します。サーバーモードを有効にするには：

1. アプリケーションの歯車アイコンをクリックして設定パネルを開きます
2. 「Application Mode」ドロップダウンで「Server Mode」を選択します
3. 「保存」をクリックして変更を適用します
4. アプリケーションを再起動します

サーバーモードでは：
- サーバーがすべてのDockerコンテナとWebサービスをホストします
- 複数のクライアントがWebブラウザを介してサーバーに接続できます
- ネットワークURL（Jupyterノートブックなど）はサーバーの外部IPアドレスを使用します
- クライアントはサーバー上でホストされているリソースにアクセスできます

詳細については[サーバーモードとスタンドアロンモード](../docker-integration/basic-architecture.md#サーバーモードとスタンドアロンモード)のドキュメントを参照してください。

## Monadic Chatの更新 :id=update

![](../assets/images/monadic-chat-menu.png ':size=240')

Monadic Chatは起動時に自動的に更新をチェックします。新しいバージョンが利用可能な場合、メインコンソールウィンドウに通知が表示されます。

更新プロセスは以下の手順に従います：

1. アプリケーションが起動すると、バックグラウンドで自動的に更新をチェックします
2. 更新が利用可能な場合、メインコンソールウィンドウにメッセージが表示されます
3. 更新をダウンロードするには、`File`→`Check for Updates`に移動します
4. バージョン情報を表示するダイアログが表示され、以下のオプションが表示されます：
   - **Download Now**：お使いのプラットフォーム用のアップデートファイルを直接ダウンロード
   - **View All Releases**：GitHubのリリースページを開く
   - **Cancel**：ダイアログを閉じる
5. 「Download Now」を選択すると、ブラウザが自動的にあなたのシステムに適したインストーラーのダウンロードを開始します
6. ダウンロードが完了したら、Monadic Chatを終了し、新しいインストーラーを実行します
7. 新しいバージョンが既存のインストールを置き換えます

システムは自動的にプラットフォーム（macOS、Windows、Linux）とアーキテクチャ（ARM64またはx64）を検出し、適切なダウンロードリンクを提供します。

[GitHub Releasesページ](https://github.com/yohasebe/monadic-chat/releases/latest)から手動で最新バージョンをダウンロードすることもできます。

## トラブルシューティング :id=troubleshooting

インストール中に問題が発生した場合は、一般的な問題と解決策についてFAQセクションを参照してください：
- [初期設定FAQ](../faq/faq-settings.md)
- [基本アプリFAQ](../faq/faq-basic-apps.md)
- [ユーザーインターフェースFAQ](../faq/faq-user-interface.md)
