# よくある開発時の問題と解決策

## ビルドの問題

### Electronパッケージングの失敗
```bash
# npmキャッシュをクリア
npm cache clean --force
rm -rf node_modules package-lock.json
npm install

# Macでの公証（notarization）の問題
export APPLE_ID="your-apple-id"
export APPLE_APP_SPECIFIC_PASSWORD="your-app-password"
```

### Dockerビルドエラー
```bash
# 完全クリーンアップ（警告：未使用イメージを削除）
docker system prune -a --volumes

# composeで再ビルド
docker compose --project-directory docker/services -f docker/services/compose.yml down
docker compose --project-directory docker/services -f docker/services/compose.yml build --no-cache
docker compose --project-directory docker/services -f docker/services/compose.yml up -d
```

## 実行時の問題

### リファクタリング後の"Cannot find module"エラー
- app/main.jsの`app.isPackaged`条件分岐を確認
- process.resourcesPathと__dirnameのパスを検証
- 必要に応じて`scripts/fix_packaged_paths.sh`を実行

### プロバイダー固有エラーでAPIテストが失敗
- mdsl/model_specのデフォルトを優先。モデルがサポートしていない可能性のあるパラメータ（例：temperature）の強制は避ける。
- 問題を切り分ける際はプロバイダーを明示的に指定：
```bash
# 選択したプロバイダーのみ実行
RUN_API=true PROVIDERS=openai,anthropic rake spec_api:smoke

# ローカルバックエンド（Ollamaなど）を除外
RUN_API=true PROVIDERS=openai,gemini rake spec_api:all
```
- 診断のためにリクエストログを有効化：
```bash
API_LOG=true RUN_API=true rake spec_api:smoke
```

### WebSocket接続の問題
1. Rubyサーバーが実行中か確認：`ps aux | grep thin`
2. ポート4567がアクセス可能か確認：`curl localhost:4567/health`
3. ブラウザコンソールでCORSエラーを確認
4. サーバーを再起動：`rake server:restart`

### SSLエラー：`certificate verify failed (unable to get certificate CRL)`

**症状**
- `rake server:debug`やチャット送信時に`SSL_connect returned=1 ... unable to get certificate CRL`が表示され、初期化やAPI呼び出しが失敗する。
- Gemini / Grok / DeepSeek / Cohereなど複数プロバイダーで同時発生し、モデル一覧（list_models）が取得できずDSLロードが止まる。

**根本原因**
- macOSなどローカル環境でCRL（Certificate Revocation List）チェック用の証明書が欠落している場合、OpenSSLのデフォルト検証が失敗する。

**解決策（2025-03）**
- `docker/services/ruby/lib/monadic/utils/ssl_configuration.rb`を追加し、起動時に`OpenSSL::SSL::SSLContext::DEFAULT_PARAMS`から`V_FLAG_CRL_CHECK / V_FLAG_CRL_CHECK_ALL`を無効化。
- `HTTP` gemの`default_options`に同じ`SSLContext`を適用し、Rubyサービス全体で統一。
- `.env`に`SSL_CERT_FILE` / `SSL_CERT_DIR`を指定すれば独自CAを優先できる。
- 既存のHTTP呼び出し（`HTTP.headers`、`Net::HTTP.start`）は新設定を共有するため追加修正は不要。

**運用上の注意点**
- フェイルセーフとして`Monadic::Utils::ProviderModelCache`を導入。`helper.list_models`が失敗するとデフォルトモデルでフォールバックしDSLロードを継続する。`EXTRA_LOGGING=true`時は`[ProviderModelCache] ... fallback`ログで検知できる。
- フォールバックが不要な運用では`ProviderModelCache.fetch`の利用箇所を調整し、明示的に`clear(:provider)`することで再取得が可能。
- 将来新たなHTTPクライアントを導入する場合は`SSLConfiguration.configure!`を再利用してCRL問題が再発しないようにする。

### LaTeX依存アプリ（Concept Visualizer / Syntax Tree）
- これらのツールはPythonサービスを`INSTALL_LATEX=true`でビルドした環境を前提に設計されている。pdflatex + dvisvgm（および必要なフォント群）が揃った状態でのみmdsl側の`disabled`条件が解除される。
- Runtimeで LaTeXツールチェーンの有無を再判定したり、フォールバックを追加する必要はない。環境が不足している場合はDockerイメージを再ビルドして整える。
- Ruby側でシェルスクリプトを組み立てる際は、`needs_cjk`のようなフラグを先にRubyで確定させてから文字列に埋め込む。未初期化のまま展開すると`bash: needs_cjk: unbound variable`のようなエラーが発生する。

### Markdownプロセスによって破損するHTMLコンテンツ

**問題**: 特殊なHTMLブロック（例：ABC記法、カスタムウィジェット）が、`smart: true`オプション付きのMarkdownコンバーターで処理されると破損する。

**症状**:
- ABC音楽記法ブロックにMarkdownテーブル構文（`|---|---|`）が表示される
- HTML属性内の直線引用符がカーリークオートに置換される
- ハイフンの代わりにEmダッシュが表示される
- 予期しない空行が挿入される

**根本原因**: HTMLブロックがスマートタイポグラフィ変換を適用する`markdown_to_html()`を通過している。

**解決策 - プレースホルダーパターン**（`lib/monadic/utils/websocket.rb:1133-1149`）:
```ruby
# 1. Markdown処理の前に特殊HTMLブロックを抽出
abc_blocks = []
text_for_markdown = text.gsub(/<div class="abc-code">.*?<\/div>/m) do |match|
  abc_blocks << match
  "\n\nABC_PLACEHOLDER_#{abc_blocks.size - 1}\n\n"
end

# 2. サニタイズされたテキストでMarkdownを処理
html = markdown_to_html(text_for_markdown, mathjax: mathjax_enabled)

# 3. Markdown処理の後に特殊ブロックを復元
abc_blocks.each_with_index do |block, index|
  html.gsub!(/<p>\s*ABC_PLACEHOLDER_#{index}\s*<\/p>/, block)
  html.gsub!("ABC_PLACEHOLDER_#{index}", block)
end
```

**重要な原則**:
- HTMLをMarkdownコンバーターで処理しない
- 変更してはいけないコンテンツにはプレースホルダーパターンを使用
- プレースホルダーを置換する際はHTML構造を正確に一致させる

**関連問題**: Chord Accompanist ABCの破損（2025-01）

### Node.js検証スクリプトへの複数行データの受け渡し

**問題**: 複数行のコード（ABC記法、Mermaid図など）をNode.jsスクリプトにコマンドライン引数として渡すと検証が失敗する。

**症状**:
- `process.argv[2]`が`undefined`になる
- エラー：`Cannot read properties of undefined (reading 'split')`
- 複雑な入力で検証がランダムに失敗する
- 検証失敗により複数の関数呼び出しがトリガーされる

**根本原因**: 特殊文字を含む複数行文字列のシェルエスケープは信頼性が低く、引数が分割または失われる。

**解決策 - コマンドライン引数の代わりにstdinを使用**:

❌ **間違い**（コマンドライン引数）:
```ruby
# 複数行/特殊文字で信頼性が低い
command = "node -e '#{validator_js}' #{Shellwords.escape(code)}"
stdout, stderr, status = Open3.capture3(command)
```

✅ **正しい**（stdin）:
```ruby
# あらゆるコンテンツで信頼できる
validator_js = self.class.abc_validator_js(abcjs_path)
stdout, stderr, status = Open3.capture3('node', '-e', validator_js, stdin_data: code)
```

**JavaScript側**:
```javascript
// process.argvの代わりにstdinから読み取る
const code = require('fs').readFileSync(0, 'utf-8');
```

**メリット**:
- あらゆるコンテンツ長に対応
- エスケープの問題がない
- 特殊文字を正しく処理
- コンテナとホスト環境の両方で動作

**関連問題**: Chord Accompanist検証ループ（2025-01）、Mermaid Grapher検証

## 開発のヒント

### Rubyコードの高速反復開発
```bash
# デバッグモードを使用してRubyコンテナをスキップ
rake server:debug

# ログを監視
tail -f ~/monadic/log/server.log
```

### 特定プロバイダーのテスト
```bash
# 特定のプロバイダーのみテスト
RUN_API=true PROVIDERS=openai,anthropic rake spec_api:smoke

# 速度向上のためメディアテストをスキップ
RUN_API=true RUN_MEDIA=false rake spec_api:all
```

### Electronパスのデバッグ
```javascript
// app/main.jsに一時的に追加
console.log('isPackaged:', app.isPackaged);
console.log('resourcesPath:', process.resourcesPath);
console.log('__dirname:', __dirname);
console.log('computed path:', computedPath);
```

## パフォーマンスの問題

### コンテナ起動が遅い
- Dockerメモリ割り当てを増やす（Docker Desktop → Settings）
- 開発時は`rake server:debug`を使用
- docker/compose.ymlで未使用コンテナを無効化

### 起動時に「Refreshing Ruby control‑plane」が頻繁に表示される
- 何が起きているか：
  - 起動時、アプリはRuby control-planeのヘルスをプローブする。`starting`状態の場合、再ビルドは不要で待機するだけで十分。
- 現在の動作：
  - アプリは`START_HEALTH_TRIES`/`START_HEALTH_INTERVAL`に基づいて待機し、ヘルスが明示的に`unhealthy`の場合のみRubyを再ビルドする。
- 調整方法：
  - 遅いマシンに対応するため待機時間を延長：
    ```
    START_HEALTH_TRIES=30
    START_HEALTH_INTERVAL=2
    ```
  - 自動リフレッシュを完全に無効化（本当に壊れている場合はメニューから手動で再ビルドが必要）：
    ```
    AUTO_REFRESH_RUBY_ON_HEALTH_FAIL=false
    ```

### テストスイートに時間がかかりすぎる
```bash
# クイックスモークテストのみ実行
RUN_API=true rake spec_api:quick

# よりクリーンな出力のためSUMMARY_ONLYを使用
SUMMARY_ONLY=1 rake spec_api:smoke
```
