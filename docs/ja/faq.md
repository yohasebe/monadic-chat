# よくある質問

## クイックナビゲーション

- [はじめに・必要条件](#はじめに・必要条件)
- [アプリケーションと機能](#アプリケーションと機能)
- [ファイルとメディアの扱い](#ファイルとメディアの扱い)
- [音声機能](#音声機能)
- [ユーザーインターフェース](#ユーザーインターフェース)
- [設定と高度な使い方](#設定と高度な使い方)
- [トラブルシューティング](#トラブルシューティング)
- [Install Options と再ビルド](#install-options-と再ビルド)

---

## はじめに・必要条件

### Q: Monadic Chatを使うにはOpenAIのAPIトークンが必要ですか？ :id=api-token-requirement

**A**: いいえ、OpenAI APIトークンは必須ではありません。以下の選択肢があります：

- **Ollamaプラグイン**: 完全無料のローカル実行オープンソースモデル
- **他のプロバイダー**: Claude、Gemini、Mistral、Cohereなどを代わりに使用
- **限定機能**: 一部の機能はAPIトークンなしで動作（基本的なUI探索）

ただし、音声認識やヘルプシステムなどの機能を最大限活用するには、OpenAI APIキーが推奨されます。

### Q: 新しいバージョンをインストールすると何が起こりますか？ :id=version-updates

**A**: 新しいバージョンをインストールすると：
- ユーザー設定（APIトークン、設定）は保持されます
- 変更内容によってDockerコンテナが再構築される場合があります
- Dockerfileに変更がある場合は完全再構築
- それ以外はRubyコンテナのみ再構築（高速）

### Q: Monadic Chatをオフラインで使用できますか？ :id=offline-usage

**A**: はい、制限付きで可能です：
- **Ollamaモデル**は完全にオフラインで動作
- **Web検索**やクラウドベースの機能にはインターネットが必要
- **ローカルコンテナ**はインターネットなしで動作継続
- **APIベースのモデル**にはインターネット接続が必要

---

## アプリケーションと機能

### Q: Code Interpreter、Coding Assistant、Jupyter Notebookアプリの違いは何ですか？ :id=app-differences

**A**: それぞれ異なる目的があります：

**Code Interpreter**
- コードを自動的に実行
- データ分析と視覚化に最適
- 隔離されたDockerコンテナでコードを実行
- 結果を即座に表示

**Coding Assistant**
- コードの作成とデバッグを支援
- コードを自動実行しない
- コード生成と説明に最適
- プログラミングガイダンスに焦点

**Jupyter Notebook**
- インタラクティブなノートブック環境
- 永続的なコード実行
- 反復的な開発に最適
- 作業を.ipynb形式で保存

### Q: プログラミングを知らなくても基本アプリを拡張できますか？ :id=extend-apps

**A**: はい！以下のことができます：
1. UIで直接システムプロンプトを変更
2. temperatureやmax tokensなどのパラメータを調整
3. カスタマイズした設定をJSONとしてエクスポート
4. 設定を他の人と共有

より深いカスタマイズには基本的なMDSLの知識が役立ちますが、簡単な変更には必須ではありません。

### Q: Monadic Chatにはどのようなウェブ検索機能がありますか？ :id=web-search

**A**: プロバイダーによってウェブ検索は異なります：

**ネイティブ検索**:
- OpenAI（gpt-4o-searchモデル）
- Anthropic Claude（web_searchツール）
- Google Gemini（Google検索）
- Perplexity（内蔵）
- xAI Grok（ライブ検索）

**Tavily API経由**:
- Mistral、Cohere、DeepSeek
- 別途Tavily APIキーが必要

---

## ファイルとメディアの扱い

### Q: テキスト以外のデータをAIエージェントに送信できますか？ :id=media-support

**A**: はい！サポートされる形式：

**直接アップロード**（プロバイダー依存）:
- 画像（PNG、JPEG、GIF、WebP）
- PDF
- 音声ファイル
- 動画ファイル

**Content Readerアプリ経由**:
- Officeドキュメント（Word、Excel、PowerPoint）
- テキストファイル
- ウェブコンテンツのURL

**処理方法**:
- 直接分析（ビジョンモデル）
- テキスト抽出
- 文字起こし（音声/動画）

### Q: PDFの内容についてAIエージェントに質問できますか？ :id=pdf-processing

**A**: はい、3つの方法があります：

1. **直接アップロード**（最も簡単）
   - 添付アイコンをクリック
   - ビジョン対応モデルで動作
   - 単一PDFに最適

2. **PDF Navigatorアプリ**
   - PDFをベクトルデータベースにインポート
   - セマンティック検索が可能
   - 大量のドキュメントコレクションに最適

3. **Code Interpreter**
   - プログラムによるPDF分析
   - 特定のデータを抽出可能
   - 構造化情報の抽出に最適

---

## 音声機能

### Q: APIキーなしでテキスト読み上げを使用できますか？ :id=tts-without-api

**A**: はい！オプション：

**Web Speech API**（内蔵）:
- 無料のブラウザベースTTS
- APIキー不要
- 品質はブラウザ/OSによって異なる

**プロバイダー固有**:
- GeminiモデルはTTSを含む
- 一部のプロバイダーには音声機能が内蔵

### Q: 音声会話をセットアップするには？ :id=voice-setup

**A**: スムーズな音声インタラクションのために：

1. **Easy Submit**を有効化（Enterキーでメッセージ送信）
2. **Auto Speech**を有効化（自動TTS再生）
3. 最適化された体験のために**Voice Chat**アプリを使用
4. 設定でSTTモデルを構成

### Q: なぜTTSが私の言語で読み上げないのですか？ :id=tts-language

**A**: 言語検出の問題は以下の場合に発生：
- テキストに複数の言語が混在
- 言語コードが正しくない
- ブラウザTTSがその言語をサポートしていない

**解決策**: TTS設定で言語を手動設定するか、発音制御のためにTTS辞書を使用

### Q: 合成音声を保存できますか？ :id=save-speech

**A**: はい、メッセージの**再生**ボタンを使用：
- ブラウザTTS: ブラウザの音声録音を使用
- APIベースのTTS: プログラムで音声を保存可能
- サードパーティツールでシステム音声をキャプチャ可能

---

## ユーザーインターフェース

### Q: メッセージボタンの役割は？ :id=message-buttons

**A**: 各メッセージには複数のアクションボタンがあります：

- **コピー**: メッセージ内容をコピー（Markdown → HTML/テキスト）
- **音声**: 音声として再生（利用可能な場合）
- **停止**: 音声再生を停止
- **削除**: メッセージ全体を削除
- **編集**: メッセージ内容を変更
- **アクティブ/非アクティブ**: コンテキスト含有を切り替え

Shiftキーを押しながらコピーをクリックすると、Markdownではなくプレーンテキストになります。

### Q: トークンはどのように計算されますか？ :id=token-counting

**A**: 表示されるトークン数には以下が含まれます：
- メッセージ内容
- システムプロンプト
- コンテキストウィンドウ
- ツール定義
- 特殊フォーマット

カウントは動的に更新され、API使用量の追跡に役立ちます。

### Q: ロールセレクターの役割は？ :id=role-selector

**A**: ロールセレクター（User/Assistant/System）により：
- **User**: 通常のユーザーメッセージ
- **Assistant**: AI応答をシミュレート
- **System**: システムレベルの指示を追加

テスト、例、会話テンプレートに便利です。

### Q: なぜlocalhostのセキュリティ警告が表示されるのですか？ :id=localhost-warning

**A**: localhostに関するブラウザの警告は正常です：
- Monadic ChatはUIをローカルで提供
- 外部サーバー接続なし
- データはあなたのマシンに留まる
- 警告は安全に無視できます

---

## 設定と高度な使い方

### Q: Monadic Chatをサーバーモードで実行するには？ :id=server-mode

**A**: サーバーモードは複数のユーザーを許可：

1. 設定で`DISTRIBUTED_MODE=true`を設定
2. `rake server`を実行
3. サーバーIPでブラウザからアクセス
4. 各ユーザーは独自のAPIキーが必要
5. セッションは分離される

### Q: Pythonライブラリを追加できますか？ :id=add-python-libraries

**A**: はい、2つの方法：

**方法1** - カスタムセットアップスクリプト:
```bash
# ~/monadic/config/pysetup.sh
pip install pandas numpy scikit-learn
```

**方法2** - アプリ内インストール:
```python
!pip install library_name
```

方法1では変更がコンテナ再起動後も保持されます。

### Q: LaTeX アプリ（Concept Visualizer / Syntax Tree）を有効にするには？ :id=enable-latex

**A**: `Actions → Install Options…` を開いて LaTeX を有効化してください。さらに OpenAI または Anthropic の API キーが必要です（キーがない場合はアプリは非表示のまま）。

### Q: 「From URL / #doc」ボタンが表示されないのはなぜ？ :id=url-doc-hidden

**A**: Selenium が無効で Tavily キーも未設定の場合、これらのボタンは非表示になります。Selenium が無効でも Tavily キーがある場合は「From URL」が Tavily を使用します。Selenium を有効化すると従来の経路に戻ります。

### Q: 再ビルドのログとヘルスチェック結果はどこで確認できますか？ :id=rebuild-logs

**A**: Save → Rebuild 後、Install Options ウィンドウに進捗と要約が表示されます。ファイルは `~/monadic/log/build/python/<timestamp>/` に保存されます：
- `docker_build.log`, `post_install.log`, `health.json`, `meta.json`

### Q: 再ビルドが遅い。高速化するには？ :id=rebuild-speed

**A**: Dockerfile をベース層とオプション層に分割しキャッシュを活用しています。キャッシュヒットを最大化するには：
- 変更するオプションを最小限にする（変更がある層のみ再実行）
- Docker のビルドキャッシュを有効にする
- `pysetup.sh` を軽量に保つ（重い処理は時間を支配）
- ネットワーク速度が apt/pip の速度に強く影響

### Q: 再ビルドに失敗したらどうなりますか？ :id=rebuild-failure

**A**: 現行イメージは保持されます（成功時のみ本番に反映する更新）。直近の実行ごとのフォルダのログを確認し、（例）`~/monadic/config/pysetup.sh` を修正して再試行してください。

### Q: NLTK と spaCy のオプションでデータやモデルは自動でダウンロードされますか？ :id=nltk-spacy-auto

**A**: いいえ。オプションはライブラリのみインストールします。
- NLTK: ライブラリのみ。コーパス/データは自動ダウンロードしません。
- spaCy: `spacy==3.7.5` のみ。`en_core_web_sm` や `en_core_web_lg` などのモデルは自動ダウンロードしません。
- `~/monadic/config/pysetup.sh` にダウンロード処理を記述し、ポストセットアップで取得してください（Pythonコンテナのドキュメントに例があります）。

### Q: TTS発音をカスタマイズするには？ :id=tts-dictionary

**A**: 発音辞書を作成：

1. CSVファイルを作成（ヘッダーなし）
2. 形式: `元の文字,発音`
3. `~/monadic/data/`に保存
4. TTS設定でパスを設定

例:
```
AI,エーアイ
SQL,エスキューエル
```

### Q: MCPとは何ですか？どのように使用しますか？ :id=mcp-integration

**A**: MCP（Model Context Protocol）により：
- 外部AIアシスタントがMonadic Chatツールを使用
- JSON-RPC 2.0プロトコル
- `MCP_SERVER_ENABLED=true`で有効化
- 自動ツール検出
- [MCP統合ドキュメント](/ja/advanced-topics/mcp-integration.md)を参照

---

## トラブルシューティング

### Q: Dockerが実行されているのにアプリが起動しないのはなぜですか？ :id=app-startup-issues

**A**: 以下の一般的な問題を確認：

1. **Docker Desktopの状態**
   - Dockerが完全に起動していることを確認
   - コンテナの状態を確認
   - 必要に応じてDockerを再起動

2. **ポートの競合**
   - ポート4567が空いている必要があります
   - 他のサービスを確認

3. **コンテナの健全性**
   - `docker ps`で確認
   - コンソールパネルでログを確認

4. **初回起動**
   - 初期コンテナのダウンロードには時間がかかる
   - コンソールで進行状況を確認

### Q: コンテナの構築に失敗した場合は？ :id=container-build-failure

**A**: トラブルシューティング手順：

1. **ログを確認**
   ```bash
   docker logs monadic-chat-ruby-container
   ```

2. **クリーン再構築**
   - Docker Desktopでコンテナを削除
   - Monadic Chatを再起動

3. **ディスク容量**
   - 15GB以上の空き容量を確保
   - 必要に応じてDockerキャッシュをクリーン

4. **ネットワークの問題**
   - インターネット接続を確認
   - 該当する場合はプロキシ設定

### Q: アプリを初期状態にリセットできますか？ :id=app-reset

**A**: はい、いくつかのオプション：

- **ソフトリセット**: メニューでアプリ名をクリック
- **コンテキストクリア**: コンテキストサイズを一時的に0に
- **完全リセット**: コンソールパネルでFile → New
- **データ削除**: 保存された会話を削除

### Q: コード実行が繰り返し失敗する場合は？ :id=code-execution-errors

**A**: Code Interpreterには再試行メカニズムがあります：
- 自動エラー検出
- 最大3回の再試行
- 一般的な問題の自己修正
- 持続する場合は以下を確認：
  - Pythonパッケージの利用可能性
  - メモリ制限
  - コード構文エラー

### Q: 複数の会話を並行して行えますか？ :id=multiple-conversations

**A**: Monadic Chatは一度に1つの会話をサポートします。ただし、以下が可能です：
- 会話の保存とエクスポート
- 異なるアプリ間の切り替え
- マルチユーザーアクセスのためのサーバーモード使用
- 複数のブラウザタブを開く（実験的）

---

## さらなるヘルプが必要ですか？

- AI支援のために**Monadic Help**アプリを使用
- 詳細なガイドは[ドキュメント](/)を確認
- [設定リファレンス](/ja/reference/configuration.md)をレビュー
- 基本については[クイックスタートチュートリアル](/ja/getting-started/quick-start.md)を参照
