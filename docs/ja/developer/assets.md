# 開発者向けCDNアセット管理

## 概要

Monadic Chatは、ローカル開発とDockerビルドのためのCDNアセット管理スクリプトを提供しています。

## ファイル

- `/docker/services/ruby/bin/assets_list.sh`: 必要なアセットを定義する中央設定ファイル
- `/bin/assets.sh`: ローカル開発用にアセットをダウンロードするスクリプト

## 新しいアセットの追加方法

新しいライブラリやアセットを追加する必要がある場合:

1. `/docker/services/ruby/bin/assets_list.sh`の`ASSETS`配列にエントリを追加します:
   ```
   "type,url,filename"
   ```

   各項目:
   - `type`: アセットタイプ（css, js, font, webfont）
   - `url`: アセットへの完全URL
   - `filename`: 保存するローカルファイル名

   例:
   ```bash
   "js,https://cdn.example.com/library.min.js,library.min.js"
   ```

2. 他の変更は必要ありません - 両方のスクリプトは同じアセットリストを使用します。

## 使用方法

ローカルで実行:
```bash
rake download_vendor_assets
```

これはアプリケーションをパッケージ化するビルドプロセス中に自動的に実行されます。

## Docker統合

アセットはDockerビルド中にダウンロードされます。Dockerバージョンのスクリプトはアセットリストを探すか、必要に応じて独自のコピーを作成します。
