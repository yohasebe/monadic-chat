# 開発者向けCDNアセット管理

## 概要

Monadic Chatは、ローカル開発とDockerビルドの両方でオフライン使用のためにサードパーティライブラリをダウンロードするCDNアセット管理スクリプトを提供しています。

## ファイル

- `/docker/services/ruby/bin/assets_list.sh`: 必要なアセットを定義する中央設定ファイル
- `/bin/assets.sh`: ローカル開発用にアセットをダウンロードするスクリプト
- `/docker/services/ruby/scripts/download_assets.sh`: Dockerビルド時に使用されるスクリプト

## 新しいアセットの追加方法

新しいライブラリやアセットを追加する必要がある場合:

1. `/docker/services/ruby/bin/assets_list.sh`の`ASSETS`配列にエントリを追加します:
   ```
   "type,url,filename"
   ```

   各項目:
   - `type`: アセットタイプ（css, js, font, webfont, mathfont）
   - `url`: CDN上のアセットへの完全URL
   - `filename`: 保存するローカルファイル名

   例:
   ```bash
   "js,https://cdn.example.com/library.min.js,library.min.js"
   ```

2. 他の変更は必要ありません - すべてのスクリプトは同じアセットリストを使用します。

## アセットタイプと保存場所

アセットはタイプ別に整理されます：
- **CSS**: `vendor/css/`に保存
- **JS**: `vendor/js/`に保存
- **フォント**: `vendor/fonts/`に保存（Montserratなどの通常フォント）
- **Webフォント**: `vendor/webfonts/`に保存（Font Awesomeなどのアイコンフォント）
- **数式フォント**: `vendor/js/output/chtml/fonts/woff-v2/`に保存（MathJax用）

## 使用方法

ローカルで実行:
```bash
rake download_vendor_assets
```

これはアプリケーションをパッケージ化するビルドプロセス中に自動的に実行されます。

## Docker統合

アセットはDockerビルド中にダウンロードされます：
- ビルド時に自動的に実行（Dockerfileの96行目）
- コンテナ内の`/monadic/public/vendor/`にダウンロード
- 既に存在するファイルはスキップ
- Font AwesomeのCSSパスの特別処理を含む（相対パスを絶対パスに変換）
- プラットフォーム固有のsedコマンドがmacOSとLinuxの違いを処理

## 現在のアセット

システムには以下が含まれています：
- **CSSフレームワーク**: Bootstrap、jQuery UI
- **JavaScriptライブラリ**: jQuery、MathJax、Mermaid、ABC.js
- **アイコンフォント**: Font Awesome
- **Webフォント**: Montserratファミリー
- **メディアライブラリ**: 音声録音用のOpus Media Recorder
