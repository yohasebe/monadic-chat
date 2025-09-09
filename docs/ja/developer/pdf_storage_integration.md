Title: PDF ストレージ統合（ローカル PGVector と OpenAI Vector Store）

概要
- ローカル／クラウドの2モードで PDF を保存・検索します（ハイブリッドは廃止）。

ルーティング
- `resolve_pdf_storage_mode(session)` が `local | cloud` を決定：
  - セッション指定 > `PDF_STORAGE_MODE`（なければ `PDF_DEFAULT_STORAGE`）> 可用性（VS/ローカルPDFの存在）
- `features.pdf_vector_storage: true` のアプリに対して、cloud 時に File Search を Responses API に注入。

ローカル（PGVector）
- アプリごとの DB 名（`monadic_user_docs_<app_key>`）で分離。
- 共通ローカル関数ツール（find_closest_text/doc、list_titles、get_text_snippet(s)）を自動付与。

クラウド（OpenAI）
- エンドポイント：
  - `POST /openai/pdf?action=upload` — Files アップロード → Vector Store へ追加
  - `GET /openai/pdf?action=list` — VS のファイル一覧＋`filename` 付与
  - `DELETE /openai/pdf?action=delete|clear` — 単体削除／全削除
- レジストリ優先で VS を解決し（`~/monadic/data/document_store_registry.json`）なければ ENV→フォールバック→作成。
- アップロード時の重複検知：SHA256＋サイズで同一判定、既存 file_id を再アタッチ（失敗時のみ1回リトライ）。

レジストリ
- 位置：`~/monadic/data/document_store_registry.json`（安全な書き込み）。
- 例：
```
{
  "chatplusopenai": {
    "cloud": {
      "vector_store_id": "vs_xxx",
      "files": [{"file_id":"file_xxx","filename":"a.pdf","hash":"sha256_size","created_at":"..."}]
    }
  }
}
```

UI
- 設定パネルに「PDF Storage Mode」（Local/Cloud）セレクタ。値は `/api/pdf_storage_defaults` に反映。
- 取り込みモーダルに個別のストレージ選択はありません。取り込みはグローバル設定に従います。
- Local/Cloud のリストを統一。個別削除・Clear All は確認ダイアログ。
- `GET /api/pdf_storage_status` で Mode／VS ID／Local有無を表示。

留意点
- クラウドはサイズ×時間で課金。空のストアは実質コストほぼゼロ。
- Electron メニュー「Clean Up Cloud PDFs」は monadic-* の Vector Store と当アプリ起源ファイルのみを対象（安全側）。
