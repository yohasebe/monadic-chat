# PDF Database

PDF Database は、一部のアプリに、会話中に AI が検索できる PDF の保存先を提供します。PDF はコンピューター上で処理・保存され、保存にも検索にも API キーは要りません。

?> **PDF Database と Knowledge Base の違い** — この2つは別の機能です。**PDF Database** パネルは、これを持つアプリ（OpenAI 版の Chat Plus と Research Assistant）でだけ表示され、アプリごとに PDF を持ちます。[Knowledge Base](../apps/knowledge-base.md) は、保存した会話とインポートしたドキュメントの別のライブラリです。一方に取り込んだ PDF がもう一方に現れることはありません。

## 仕組み

- PDF はコンピューター上で処理・検索され、オフラインでも使えます
- PDF は Monadic Chat の Docker ボリュームに保存されます

## PDFコレクションの管理

Web インターフェースの PDF Database パネル（その Local PDF の欄）でインポート済みドキュメントを管理できます。

- **Import**: 新しい PDF をアップロードします。バックグラウンドで処理されます
- **Refresh**: 最近追加されたドキュメントを表示するためにリストを更新します
- **削除（項目ごと）**: 確認付きで個別の PDF を削除します
- **Clear All**: 現在のアプリのすべての PDF を確認付きで削除します

あるアプリでインポートした PDF が、別のアプリに現れることはありません。

## 注意事項

- **データの永続化**: ドキュメントは `monadic-chat-qdrant-data` Docker ボリュームに保存されます
- **バックアップ**: Actions メニューの **Export Document DB** でバックアップ（暗号化または平文）、**Import Document DB** で復元できます
- **コンテナの再構築**: データ損失を防ぐため、コンテナを再構築する前にデータベースをエクスポートしてください
