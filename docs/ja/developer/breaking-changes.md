# バージョン1.0.0の重要な変更

このページでは、以前のバージョンからの重要な変更を文書化し、Monadic Chat 1.0.0への移行を支援します。

## バージョン 1.0.0-beta.1

### 設定システムの変更

1.0.0での最も重要な変更は、統一された設定システムです。

#### 変更内容
- **すべてのAPIキーと設定は`~/monadic/config/env`に配置する必要があります**
- 環境変数はユーザー設定のフォールバックとして使用されなくなりました
- これによりUIとバックエンドの動作の一貫性が確保されます

#### 影響を受ける設定
- すべてのAPIキー: `OPENAI_API_KEY`、`ANTHROPIC_API_KEY`、`GEMINI_API_KEY`など
- デフォルトモデル: `OPENAI_DEFAULT_MODEL`、`ANTHROPIC_DEFAULT_MODEL`など
- 機能設定: `AI_USER_MAX_TOKENS`、`WEBSEARCH_MODEL`、`DISTRIBUTED_MODE`
- その他の設定: `PYTHON_PORT`、`HELP_EMBEDDINGS_BATCH_SIZE`、`TTS_DICT_DATA`

#### 移行手順
1. 環境変数に設定されているAPIキーや設定を確認
2. これらの値を`~/monadic/config/env`にコピー
3. 混乱を避けるため環境変数を削除

#### この変更の理由
- すべての設定の単一の情報源
- UIとバックエンドが一貫して動作
- デバッグとトラブルシューティングが容易
- ElectronアプリのGUI設定との整合性向上

### 埋め込みモデルの変更

#### 変更内容
- **`text-embedding-3-large`（3072次元）のみを使用**
- 設定から`text-embedding-3-small`オプションが削除されました
- より大きな次元に対応するためヘルプデータベースのスキーマが変更されました

#### 移行手順
1. 1.0.0へのアップデート後、ヘルプデータベースを再構築：
   ```bash
   rake help:rebuild
   ```
2. PDF Navigatorユーザーの場合、既存の埋め込みは引き続き動作します
3. 新しい埋め込みは自動的に新しいモデルを使用します

#### この変更の理由
- より正確な検索結果のための高品質な埋め込み
- 設定の簡素化（埋め込みモデルを選択する必要がない）
- すべての埋め込み機能で一貫したパフォーマンス

### APIとコードの変更

#### 削除されたメソッド
- `run_script`メソッドが削除されました
- すべてのプロバイダが`run_code`のみを使用します

#### アプリ開発者向けの移行
`run_script`を使用しているカスタムアプリがある場合：
```ruby
# 古い方法（動作しません）
run_script(script: "example.py", args: ["arg1", "arg2"])

# 新しい方法
run_code(code: File.read("example.py"), command: "python", extension: "py")
```

#### Pythonスクリプトの再編成
スクリプトがカテゴリ別ディレクトリに再編成されました：
- `utilities/` - システムおよびユーティリティスクリプト
- `cli_tools/` - コマンドラインツール
- `converters/` - ファイル形式コンバーター
- `services/` - APIサービス

#### ファイル名の変更
- `sysinfo` → `sysinfo.sh`
- `app.py` → `flask_server.py`

### Rubyバージョン要件

- 最小Rubyバージョンは2.6.10になりました
- これにより、すべての依存関係との互換性が確保されます

### 音声入力に関する注意

音声入力機能はOpenAIのWhisper APIを使用し、動作するには設定ファイルに`OPENAI_API_KEY`が必要です。これは変更ではありませんが、環境変数のフォールバックが利用できなくなったため注意が必要です。

## 現在のバージョンの確認

現在のバージョンを確認するには：
1. デスクトップアプリで**ファイル** → **Monadic Chatについて**をクリック
2. またはソースコードの`version.rb`ファイルを確認

## ヘルプの取得

移行中に問題が発生した場合：
1. [トラブルシューティングガイド](troubleshooting.md)を確認
2. 詳細な変更については[Changelog](../ja/changelog.md)を確認
3. [GitHub](https://github.com/yohasebe/monadic-chat/issues)でissueを開く