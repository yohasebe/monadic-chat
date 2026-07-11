# FAQ：初期設定

##### Q: Monadic Chatを使うのにOpenAIのAPIトークンは必要ですか？ :id=openai-api-token-requirement

**A**: 音声認識、音声合成、テキストエンベディングの作成などの機能を使用しない場合は、OpenAIのAPIトークンは必ずしも必要ではありません。Anthropic Claude、Google Gemini、Cohere、Mistral AI、DeepSeek、xAI GrokなどのAPIを使用することもできます。

商用のAPIを使いたくない場合は、Ollamaを使用してローカル言語モデルを実行できます：
1. [https://ollama.com/download](https://ollama.com/download) からOllamaをインストール
2. `ollama pull <model>` コマンドでモデルを取得（例：`ollama pull llama3.2`）
3. Ollamaプロバイダーを選択してChatアプリを使用

Monadic ChatでOllamaを使用する詳細については、[Ollamaの利用](../advanced-topics/ollama.md) を参照してください。

---

##### Q: Monadic Chatの再構築（コンテナ群のrebuild）に失敗します。どうしたらいいですか？ :id=container-rebuild-failures

**A**: ログフォルダ内のログファイルを確認してください。

追加アプリの開発や、既存アプリの変更などを行っている場合は、ログフォルダ内の `server.log` の内容を確認してください。エラーメッセージが表示されている場合は、その内容に基づいて、アプリのコードの修正を行ってください。

`pysetup.sh` を使ってPythonコンテナにライブラリを追加している場合は、`docker_build.log` にエラーメッセージが表示されることがあります。エラーメッセージを確認して、インストールスクリプトを修正してください。

---

##### Q: UI言語と会話言語の違いは何ですか？ :id=ui-vs-conversation-language

**A**: Monadic Chatには2つの独立した言語設定があります：

- **UI言語**: Electronアプリのインターフェース言語（メニュー、ボタン、ダイアログ）を制御します。Electron設定パネルで設定し、アプリケーションのインターフェースのみに影響します。

- **会話言語**: AI応答と音声認識・合成に使用される言語を制御します。Web UIで設定し、以下に影響します：
  - AI応答言語
  - 音声認識（STT）の言語検出
  - 音声合成（TTS）の言語
  - テキスト方向（アラビア語、ヘブライ語、ペルシャ語、ウルドゥー語のRTL）

これらの設定は独立しているため、アプリのインターフェースを一つの言語で使用しながら、別の言語でAIと会話することができます。

---

##### Q: LaTeXを使うアプリ（Concept Visualizer / Syntax Tree）を有効にするにはどうすればよいですか？ :id=enable-latex

**A**: `Actions → Install Options…` を開いてLaTeXオプションを有効にし、Pythonコンテナを再構築してください。再構築時にTeX Live（XeLaTeX/LuaLaTeX）、dvisvgm/pdf2svg、Ghostscript、CJKフォントパッケージがインストールされ、Concept VisualizerやSyntax Treeで日本語・中国語・韓国語を含む図が描画できるようになります。これらのアプリはOpenAIとAnthropic Claude向けに提供されているため、いずれかのAPIキーが設定されていない場合は表示されません。

---

##### Q: NLTKやspaCyのインストールオプションを有効にすると、データセットやモデルも自動的にダウンロードされますか？ :id=nltk-spacy-auto

**A**: いいえ。イメージを軽量に保つため、オプションはライブラリのみをインストールします：

- **NLTK**: ライブラリのみインストールされます。コーパスやデータセットはダウンロードされません。
- **spaCy**: ライブラリのみインストールされます。言語モデル（例：`en_core_web_sm`）はダウンロードされません。

データセットやモデルの取得には `~/monadic/config/pysetup.sh` を使用してください。例については[Pythonコンテナ](../docker-integration/python-container.md)の「追加ライブラリ（pysetup.sh）」を参照してください。

---

##### Q: 再構築のログやヘルスチェックの結果はどこで確認できますか？ :id=rebuild-logs

**A**: Install Optionsの保存は設定の更新のみを行います。再構築自体は、次回のStart時（「Rebuild and Start」を選べるダイアログが表示されます）または `Actions → Build Python Container` の実行時に行われます。ビルド関連のファイルは `~/monadic/log/` に保存されます：

- `docker_build_python.log` — Dockerビルドの出力
- `post_install_python.log` — ポストインストール（`pysetup.sh`）の出力
- `python_health.json` — ビルド後のヘルスチェック結果
- `python_meta.json` — ビルドのメタデータ
- `python_build_options.txt` — 前回のビルドで使用したオプションの記録

---

##### Q: 再構築に時間がかかります。速くする方法はありますか？ :id=rebuild-speed

**A**: Monadic Chatは最速のビルド戦略を自動的に選択します：

- **インストールオプションをすべて無効にしている場合**: ローカルでビルドせず、ビルド済みのデフォルトPythonイメージをダウンロードします（数秒〜数分）。
- **一部のオプションを有効にしている場合**: ビルド済みイメージのレイヤーをDockerキャッシュ経由で再利用し、有効にしたオプションのレイヤーだけを実際にビルドします。
- **手動ビルド（`Actions → Build Python Container`）**: 確実性を優先した `--no-cache` のクリーンビルドで、最も時間がかかる経路です。

その他のヒント: `~/monadic/config/pysetup.sh` は軽量に保ってください（重いインストールがビルド時間の大半を占めます）。また、ダウンロードの多い工程はネットワーク速度の影響を大きく受けます。再構築後、Pythonコンテナは新しいイメージを使用するために自動的に再起動します。

---

##### Q: 再構築に失敗した場合はどうなりますか？ :id=rebuild-failure

**A**: 現在動作しているイメージは保持されます。新しいイメージへの置き換えはビルドが成功した場合にのみ行われます（アトミックな更新）。`~/monadic/log/` の `docker_build_python.log` と `post_install_python.log` を確認し、問題（たとえば `~/monadic/config/pysetup.sh` の内容）を修正してから再試行してください。

---

##### Q: Rubyコンテナの再構築はいつ実行されますか？頻繁な再構築を避けられますか？ :id=ruby-rebuild-when

**A**: Rubyコンテナの再構築は必要な場合にのみ実行されます：

- **アプリのバージョン更新時**: 新しいバージョンをインストールした後のStart時に、Dockerキャッシュを利用してRubyコンテナを再構築します（高速）。
- **Gem依存関係の変更時**: フィンガープリント（`Gemfile` + `monadic.gemspec` のSHA-256）を現在のイメージと比較し、不一致の場合に再構築します。可能な限りDockerキャッシュでbundleレイヤーを再利用します。
- **起動時ヘルスプローブの失敗時**: Start時にオーケストレーションの健全性を確認します（たとえばPythonコンテナの再構築後など）。Rubyコンテナが unhealthy の場合、キャッシュを活用した1回限りのリフレッシュが自動実行され、起動が継続されます。この動作は `~/monadic/log/docker_startup.log` に記録されます（`Auto-rebuilt Ruby due to failed health probe`）。プローブは `~/monadic/config/env` の `START_HEALTH_TRIES` と `START_HEALTH_INTERVAL` で調整できます。

診断目的でクリーンビルドを強制するには、`~/monadic/config/env` に `FORCE_RUBY_REBUILD_NO_CACHE=true` を設定するか、`Actions → Build Ruby Container` を使用してください。

