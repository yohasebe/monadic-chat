# アプリ開発者のためのファイル構成

このガイドでは、Monadic Chatでカスタムアプリやスクリプトを配置する場所について説明します。

## ユーザーディレクトリの構造

Monadic Chatのユーザーディレクトリ (`~/monadic/`) には、以下のものが含まれています。

```text
~/monadic/
├── config/           # 設定ファイル
│   ├── env           # APIキーと設定
│   ├── rbsetup.sh    # Rubyセットアップスクリプト（オプション）
│   ├── pysetup.sh    # Pythonセットアップスクリプト（オプション）
│   └── olsetup.sh    # Ollamaセットアップスクリプト（オプション）
├── data/             # データとカスタムコンテンツ
│   ├── apps/         # カスタムアプリの配置場所
│   ├── scripts/      # カスタムスクリプト
│   ├── plugins/      # MCPサーバープラグイン
│   └── help/         # ヘルプシステムのドキュメント
└── logs/             # アプリケーションログ
```

## カスタムアプリの作成

### アプリのディレクトリ構造
アプリは `~/monadic/data/apps/` に配置します。

```text
~/monadic/data/apps/
└── my_custom_app/
    ├── my_custom_app_openai.mdsl    # アプリ定義
    ├── my_custom_app_tools.rb       # 共有ツール（オプション）
    └── my_custom_app_openai.rb      # Ruby実装（オプション）
```

### 命名規則
**重要**: アプリ名はRubyのクラス名と一致させる必要があります。
- ファイル: `chat_assistant_openai.mdsl`
- アプリ名: `app "ChatAssistantOpenAI"`
- クラス名: `class ChatAssistantOpenAI < MonadicApp`

## カスタムスクリプト

カスタムスクリプトは `~/monadic/data/scripts/` に配置します。
- スクリプトは自動的に実行可能になります。
- PATHに追加されるため、名前で呼び出すことができます。
- `.sh`、`.py`、`.rb` など、さまざまな実行可能形式をサポートしています。

例:
```text
~/monadic/data/scripts/
├── my_analyzer.py
├── data_processor.rb
└── utility.sh
```

## 組み込みアプリの場所

組み込みアプリはDockerコンテナ内の以下の場所にあります。
```text
/monadic/apps/
├── chat/
├── code_interpreter/
├── research_assistant/
└── ...
```
これらを独自のアプリの例として使用できます。

## ログとデバッグ

- アプリケーションログ: `~/monadic/logs/`
- 詳細なログについては、コンソールパネルで「Extra Logging」を有効にしてください。
- デバッグには、Rubyコードで `puts` 文を使用します。

## ベストプラクティス

1. **機能ごとに整理する**: 関連するアプリをサブディレクトリにグループ化します。
2. **明確な名前を使用する**: アプリの目的が名前から明らかになるようにします。
3. **バックアップを保持する**: 大幅な変更を加える前に、動作するアプリのコピーを保存します。
4. **段階的にテストする**: 機能を追加するたびにテストします。

## 一般的なファイルタイプ

| 拡張子 | 目的 | 例 |
|-----------|---------|---------|
| `.mdsl` | アプリ定義 | `chat_bot_openai.mdsl` |
| `.rb` | Ruby実装 | `chat_bot_tools.rb` |
| `.py` | Pythonスクリプト | `data_analyzer.py` |
| `.sh` | シェルスクリプト | `backup.sh` |

## 次のステップ

- 完全なチュートリアルについては、[アプリ開発](develop_apps.md)を参照してください。
- 構文のリファレンスについては、[Monadic DSL](monadic_dsl.md)を確認してください。
- 既存のアプリを独自のアプリのテンプレートとして使用してください。
