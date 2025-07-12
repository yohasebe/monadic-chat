# アプリ開発者のためのファイル構成

このガイドでは、Monadic Chatでカスタムアプリとスクリプトを配置する場所を説明します。

## ユーザーディレクトリ構造

Monadic Chatのユーザーディレクトリ（`~/monadic/`）の内容：

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
│   └── help/         # ヘルプシステムドキュメント
└── logs/             # アプリケーションログ
```

## カスタムアプリの作成

### アプリディレクトリ構造
アプリを`~/monadic/data/apps/`に配置します：

```text
~/monadic/data/apps/
└── my_custom_app/
    ├── my_custom_app_openai.mdsl    # アプリ定義
    ├── my_custom_app_tools.rb       # 共有ツール（オプション）
    └── my_custom_app_openai.rb      # Ruby実装（オプション）
```

### 命名規則
**重要**：アプリ名はRubyクラス名と一致する必要があります：
- ファイル：`chat_assistant_openai.mdsl`
- アプリ名：`app "ChatAssistantOpenAI"`
- クラス名：`class ChatAssistantOpenAI < MonadicApp`

## カスタムスクリプト

カスタムスクリプトを`~/monadic/data/scripts/`に配置します：
- スクリプトは自動的に実行可能になります
- PATHに追加されるので名前で呼び出せます
- `.sh`、`.py`、`.rb`およびその他の実行可能形式をサポート

例：
```text
~/monadic/data/scripts/
├── my_analyzer.py
├── data_processor.rb
└── utility.sh
```

## 組み込みアプリの場所

組み込みアプリはDockerコンテナ内の以下の場所にあります：
```text
/monadic/apps/
├── chat/
├── code_interpreter/
├── research_assistant/
└── ...
```

これらを自分のアプリの例として使用できます。

## ログとデバッグ

- アプリケーションログ：`~/monadic/logs/`
- 詳細なログのためにコンソールパネルで「Extra Logging」を有効化
- デバッグのためにRubyコードで`puts`文を使用

## ベストプラクティス

1. **機能別に整理** - 関連するアプリをサブディレクトリにグループ化
2. **明確な名前を使用** - アプリの目的を名前から明らかにする
3. **バックアップを保持** - 大きな変更を行う前に動作するアプリのコピーを保存
4. **段階的にテスト** - 機能を追加するたびにテスト

## 一般的なファイルタイプ

| 拡張子 | 用途 | 例 |
|--------|------|-----|
| `.mdsl` | アプリ定義 | `chat_bot_openai.mdsl` |
| `.rb` | Ruby実装 | `chat_bot_tools.rb` |
| `.py` | Pythonスクリプト | `data_analyzer.py` |
| `.sh` | シェルスクリプト | `backup.sh` |

## 次のステップ

- 完全なチュートリアルは[アプリ開発](./develop_apps.md)を参照
- 構文リファレンスは[Monadic DSL](../advanced-topics/monadic_dsl.md)を確認
- 既存のアプリを自分のアプリのテンプレートとして使用