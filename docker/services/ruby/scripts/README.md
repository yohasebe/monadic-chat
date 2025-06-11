# Monadic Chat Scripts

このディレクトリには、Monadic Chatの開発・運用に役立つ各種スクリプトが整理されています。

## ディレクトリ構造

### `/utilities/`
ビルドやセットアップに必要な汎用ユーティリティスクリプト
- `download_assets.sh` - 必要なアセット（CSS、JS、フォント等）をダウンロード
- `fix_font_awesome_paths.sh` - Font Awesomeのパスを修正

### `/cli_tools/`
コマンドラインから直接実行できる各種ツール
- `content_fetcher.rb` - ファイルの内容を読み取り、バイナリチェックを行う
- `image_query.rb` - 画像をBase64エンコードしてOpenAI APIに問い合わせる
- `stt_query.rb` - 音声ファイルから文字起こし（Speech-to-Text）
- `tts_query.rb` - テキストから音声生成（Text-to-Speech）
- `video_query.rb` - 動画ファイルの解析とフレーム抽出

### `/generators/`
コンテンツを生成するスタンドアロンツール
- `image_generator_grok.rb` - Grok APIを使用した画像生成
- `image_generator_openai.rb` - OpenAI DALL-E APIを使用した画像生成
- `video_generator_veo.rb` - Google Veo APIを使用した動画生成

### `/diagnostics/`
各機能の診断・テスト用スクリプト
- `/apps/concept_visualizer/` - Concept Visualizerアプリの診断ツール
- `/apps/wikipedia/` - Wikipedia機能のテストツール

## 使用方法

### CLIツールの例

```bash
# ファイル内容を取得（最大10MBまで）
ruby scripts/cli_tools/content_fetcher.rb /path/to/file.txt

# 画像について質問
ruby scripts/cli_tools/image_query.rb /path/to/image.png "What is in this image?"

# 音声を文字起こし
ruby scripts/cli_tools/stt_query.rb /path/to/audio.mp3
```

### 診断ツールの例

```bash
# Concept Visualizerの基本機能テスト
cd scripts/diagnostics/apps/concept_visualizer/
./test_concept_visualizer_simple.sh

# Wikipedia読み込みテスト
ruby scripts/diagnostics/apps/wikipedia/test_wikipedia_loading.rb
```

## 注意事項

- 多くのスクリプトはAPIキーの設定が必要です（`OPENAI_API_KEY`等）
- 診断スクリプトはDockerコンテナが起動している状態で実行してください
- CLIツールは独立して動作しますが、必要な依存関係がインストールされている必要があります