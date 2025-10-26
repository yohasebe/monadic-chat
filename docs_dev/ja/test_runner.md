タイトル：統合テストランナーとレポート（内部向け）

スコープ
- このドキュメントはMonadic Chatメンテナー向けです。公開アプリ開発者向けドキュメントは`docs/`配下にあります。内部実装の詳細は`docs_dev/`に属します。

概要
- 統合ランナーは、Ruby（unit/integration/API）、JavaScript（Jest）、Pythonテストをオーケストレーションします。
- Rubyスイートは、デフォルトでJSON、HTML、コンパクトテキストレポートを保存します。

クイックスタート
- 基本的なテスト実行（Ruby + JavaScript + Python、API呼び出しなし）：
  - `rake test`
- 包括的なテストスイート（API テスト付き、macOSで自動でインデックスを開く）：
  - `rake test:all[standard,true]`
- メディアテスト含む完全テストスイート（画像/動画/音声生成）：
  - `rake test:all[full]`
- 実際のAPI呼び出しなしで高速ローカル実行：
  - `rake test:all[none]`

アーティファクト
すべてのテスト結果は`./tmp/test_results/`に集中保存されます：

- **Ruby (RSpec)**：
  - `tmp/test_results/<run_id>/`（完全な結果を含むディレクトリ）
  - `tmp/test_results/<run_id>/summary_compact.md`（簡潔なサマリー）
  - `tmp/test_results/<run_id>/summary_full.md`（詳細な結果）
  - `tmp/test_results/<run_id>/rspec_report.json`（機械可読形式）
  - `tmp/test_results/latest/`（最新実行へのシンボリックリンク）

- **JavaScript (Jest)**：
  - `tmp/test_results/<run_id>_jest.json`（JSON形式のテスト結果）

- **Python (pytest)**：
  - `tmp/test_results/<run_id>_pytest.txt`（テスト出力）

- **統合テストスイート**：
  - `tmp/test_results/all_<timestamp>.json`（統合サマリー）
  - `tmp/test_results/index_all_<timestamp>.html`（HTMLレポートインデックス）

APIレベル
- `full`：メディア生成を含むすべてのテスト（画像/動画/音声）
- `standard`：メディア生成なしのAPIテスト（デフォルト）
- `none`：ローカルテストのみ、API呼び出しなし

Rakeタスク
- `rake test` – 全テスト実行（Ruby + JavaScript + Python、APIなし）
- `rake test:help` – スイートとオプションをリスト。
- `rake test:run[suite,opts]` – 単一スイートを実行。以下を受け入れます：
  - `api_level=full|standard|none`（デフォルト：`standard`）
  - `format=doc|progress|json`
  - `save=true|false`（デフォルト：true）、`html=true|false`（デフォルト：true）、`text=true|false`（デフォルト：true）
  - `docker=auto|on|off`（integration/systemのみ）
  - `run_id=...`（自動IDを上書き）
- `rake test:all[api_level,open]` – すべてのスイートをオーケストレーション。`open=true`はmacOSでインデックスを開きます。
- `rake test:report[run_id]` – 最新または特定の実行のHTMLを生成。
- `rake test:history[count]`、`rake test:compare[run1,run2]` – 保存された実行を閲覧/比較。
- `rake test:cleanup[keep_count]` – 古いテスト結果をクリーンアップ（デフォルト：最新3件を保持）。

実装ノート
- ランナーは、利用可能な場合は`~/monadic/config/env`からenvデフォルトをロードします。
- JSON分析は失敗/保留を抽出し、CLIツール用のコンパクトテキストレポートを書き込みます。
- インデックスHTMLは、利用可能な場合にスイートごとのレポートを集約します。JS/Pythonは現在合格/不合格のみを表示します。

根拠
- デフォルトオンレポートは、CI統合を必要とせずに開発者のフィードバックループを改善します。アーティファクトはローカルレビューと共有に適しています。

トラブルシューティング
- タスクをリストする際のRSpec rakeタスクロードエラー：`cannot load such file -- rspec/core/rake_task`
  - 原因：グローバル`rspec` gemが不足。統合ランナーは必要ありませんが、`rake -T`がロードを試みる可能性があります。
  - 修正：非RSpecタスクでは無視するか、スタンドアロンRSpecタスクが必要な場合は`docker/services/ruby`で`bundle install`を実行します。
- 結果が保存されない / ディレクトリが見つからない
  - 確認：`tmp/test_results/`が存在すること。ランナーは自動的に作成しますが、権限がブロックする可能性があります。
  - チェック：`ls -la tmp/ && chmod 755 tmp && mkdir -p tmp/test_results`。
- APIキーが設定されていない
  - オフライン実行の場合は、`api_level=none`を優先します。
  - API実行の場合は、`~/monadic/config/env`でキーを設定します（例：`OPENAI_API_KEY=...`）。
- Dockerが実行されていない（integration/system）
  - Docker Desktopを起動し、`pgvector`コンテナが利用可能であることを確認します。
  - または、それを必要としないターゲット実行では`docker=off`でバイパスします。
- 長い実行時間 / タイムアウト
  - タイムアウトを増やす：`rake test:run[integration,"timeout=120"]`。
  - API使用を制限：高速ターンアラウンドのため`api_level=none`。
- 大規模スイートでのメモリ圧迫
  - スイートを個別に実行します。同時実行の重いワークロードを避けます。

プロファイル（例）
- `config/test/test-config.yml`（フォールバック：`.test-config.yml`）で再利用可能なプロファイルを定義し、`rake test:profile[ci]`で実行します。

例：
```
profiles:
  quick:
    suites: [unit]
    timeout: 30

  ci:
    suites: [unit, integration]
    format: json
    save: true
    docker: auto

  full:
    suites: [unit, integration, api]
    providers: [openai, anthropic]
    timeout: 120
    save: true
    format: documentation
    docker: auto
```

サンプル出力
- インデックスHTML：`tmp/test_results/index_all_<timestamp>.html`は、ステータスと詳細レポートへのリンクを含むスイートごとのカードをリストします。
- スイートごとのHTML：`tmp/test_results/report_<run_id>.html`は、要約カウントを表示し、場所を含む失敗/保留を列挙します。
- コンパクトテキスト要約：`tmp/test_results/<run_id>_report.txt`は、合計、タイミング、および失敗/保留の番号付きリストを含みます。

ヒント
- macOS自動オープン：`rake test:all[standard,true]`は、完了時にインデックスページを開きます。
- カスタム実行ID：`run_id=my_run_001`を渡して、アーティファクトを予測可能にグループ化します。
- 自動クリーンアップ：`TEST_AUTO_CLEANUP=true`を設定してテスト後に古い結果を自動削除。
- 保持ポリシー：`TEST_KEEP_COUNT=10`を設定してより多くのテスト結果を保持（デフォルト：3）。

クリーンアップ管理
- 手動クリーンアップ：`rake test:cleanup`（デフォルトで最新3件を保持）
- カスタム保持：`rake test:cleanup[10]`（最新10件を保持）
- 自動クリーンアップ：`TEST_AUTO_CLEANUP=true rake test`（テスト実行後にクリーンアップ）
- ディスク使用量確認：`du -sh tmp/test_results`
