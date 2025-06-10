---
sidebar_label: コード構成
---

# コード構成とファイル構造

このドキュメントでは、Monadic Chat の Ruby バックエンドコードのディレクトリおよびファイル構造を説明します。対象パスは `docker/services/ruby/lib/monadic` です。

## ディレクトリレイアウト

```text
docker/services/ruby/
├── lib/monadic/
│   ├── version.rb        # Monadic Chatのバージョン定義
│   ├── monadic.rb        # エントリポイントおよび環境設定の読み込み
│   ├── app.rb            # MonadicAppクラスとアプリケーションローダー
│   ├── dsl.rb            # Monadic DSLローダーと定義
│   ├── agents/           # ビジネスロジック用エージェントモジュール
│   │   ├── ai_user_agent.rb
│   │   └── ...
│   ├── adapters/         # 外部連携およびヘルパーモジュール
│   │   ├── bash_command_helper.rb
│   │   ├── file_analysis_helper.rb
│   │   └── ...
│   │   └── vendors/      # サードパーティAPIクライアントヘルパー
│   │       ├── openai_helper.rb
│   │       └── ...
│   └── utils/            # 共通ユーティリティ関数
│       ├── string_utils.rb
│       ├── interaction_utils.rb
│       └── ...
├── apps/                 # アプリケーション定義（自動読み込み）
│   ├── chat/
│   ├── code_interpreter/
│   └── ...
├── scripts/              # ユーティリティと診断スクリプト
│   ├── utilities/        # ビルドとセットアップユーティリティ
│   ├── cli_tools/        # コマンドラインツール
│   ├── generators/       # コンテンツジェネレーター
│   └── diagnostics/      # テストと診断スクリプト
│       └── apps/         # アプリ別テスト
└── spec/                 # RSpecテストファイル
```

## 各層の説明

- **version.rb**: Monadic Chat のバージョン情報を定義します。
- **monadic.rb**: 依存関係の読み込み、環境設定の初期化、ユーティリティ設定、アプリケーションの初期化を行います。
- **app.rb**: `MonadicApp` クラスを含み、adapters と agents の読み込み、`send_command` や `send_code` といったコアメソッドを定義します。
- **dsl.rb**: レシピファイル（`.rb`）および DSL ファイル（`.mdsl`）を読み込むローダーを実装します。
- **agents/**: ビジネスロジック用エージェントモジュールを格納します。
- **adapters/**: コマンド実行やコンテナ操作などの外部連携モジュールを格納します。`vendors/` サブフォルダには API クライアントヘルパーを配置します。
- **utils/**: 文字列操作、ファイル I/O、埋め込み処理、セットアップスクリプトなどの純粋ユーティリティを格納します。

この構造により、**agents**, **adapters**, **utils** が明確に区分され、コードベースの理解や拡張が直感的に行える構成です。

## 重要な注意事項

### アプリの読み込み
- `apps/` ディレクトリ内のすべての `.rb` および `.mdsl` ファイルは初期化時に自動的に読み込まれます
- アプリ内の `test/` サブディレクトリ内のファイルは、テストスクリプトがアプリケーションとして読み込まれないように無視されます
- テストスクリプトは代わりに `scripts/diagnostics/apps/` に配置してください

### スクリプトの構成
- **utilities/**: ビルドとセットアップタスク用のスクリプト
- **cli_tools/**: スタンドアロンのコマンドラインツール（旧 `simple_*.rb`）
- **generators/**: コンテンツ（画像、動画など）を生成するスクリプト
- **diagnostics/**: アプリ別に整理されたテストと診断スクリプト