# Electron：開発環境と本番環境のパス

Monadic Chatは`app.isPackaged`を使用して、スクリプト、アイコン、プリロード、静的アセットのパスを分岐します。

一般的なパターン（`app/main.js`参照）：
- アイコンディレクトリ：
  - パッケージ版：`path.join(process.resourcesPath, 'icons')`
  - 開発版：`path.join(__dirname, 'icons')`
- プリロードスクリプト：
  - パッケージ版：`path.join(process.resourcesPath, 'preload.js')`
  - 開発版：`path.join(__dirname, 'preload.js')`
- Monadicシェルスクリプトと静的ファイルは同じパターンに従う

ヒント：
- `app.isPackaged`を使用する（`path.isPackaged`ではない）
- 本番環境では`process.resourcesPath`から派生した絶対パスを優先
- パッケージング後に実行されるコードでは、`app.isPackaged`でガードしない限り`__dirname`を避ける
- シェルコマンドを呼び出す際にパスを引用符で囲み、プラットフォームの違いを考慮
- `electron .`を実行する際、相対パスが`app/`から正しく解決されることを確認

パス問題のデバッグ：
- `app/main.js`の計算されたパスの周辺に一時的なログを追加
- DevToolsを開いてプリロードAPIが利用可能かどうかを確認して`preload.js`の解決を検証
