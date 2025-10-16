タイトル：ベクトルDB - レジストリと重複排除（ハイブリッド削除済み）

概要
- 目的（履歴）：ローカル（PGVector）とクラウド（OpenAI Vector Store）をアプリスコープのストレージで統一。
- 注意：ハイブリッドルーティングはアプリケーションから削除されました。このドキュメントは履歴的な参照として残されています。

コアコンポーネント
- レジストリ（データ）：`~/monadic/data/document_store_registry.json`
  - アトミック書き込み（tmp→rename）
  - アプリごと：`cloud.vector_store_id`、`cloud.files[] (file_id, filename, hash, created_at)`
- ルーティングモード（現在）：`local | cloud`（ハイブリッド削除済み）
  - mode = `cloud`かつアプリが`pdf_vector_storage: true`の場合、Responses API file_searchが注入される
- ローカルツール：`MonadicApp`の汎用ハンドラー（find/list/get）、アプリごとのDB名`monadic_user_docs_<app_key>`

エンドポイント
- `/openai/pdf?action=upload` — ファイルをアップロード、SHA256+sizeで重複排除、アプリVSに添付、レジストリを更新
- `/openai/pdf?action=list` — VSファイルをリスト。`vector_store_id`を返す
- `/openai/pdf?action=delete|clear` — 単一/すべてを削除。それに応じてレジストリを更新
- `/api/pdf_storage_status` — モード、vs id、ローカル/クラウドの存在を返す

プロンプトノート
- プロンプトは単一の設定されたソース（ローカルまたはクラウド）を反映し、ハイブリッドには言及しません。

クリーンアップ（Electron）
- 「クラウドPDFをクリーンアップ」：monadic-* Vector Storesとアプリ起源ファイルのみを削除（サードパーティの使用を保護）。

ランタイム設定リフレッシュ
- `Monadic::Utils::PdfStorageConfig`は再起動なしで`CONFIG`を`~/monadic/config/env`と同期させます。
- `refresh_from_env`はPDFリクエストを処理する前にエンドポイントによって呼び出されます。envファイルのmtimeが変更されると、`PDF_STORAGE_MODE`/`PDF_DEFAULT_STORAGE`を再ロードします。
- 空の値は`CONFIG`からキーを削除するため、envファイルから行を削除すると、次回リクエストが処理される際にすぐにデフォルトにフォールバックします。
- 仕様は`reset_tracking!`を呼び出して、次のリクエストでenvファイルを強制的に再読み込みできます。

未解決の項目
- レジストリをローカルスコープに拡張（ネームスペース移行）、リストUI、重複排除フローの統合テスト。
