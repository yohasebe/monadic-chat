Title: PDFストレージ（ローカル／クラウド）

概要
- Monadic Chat は PDF を知識ベースとして保存し、内容に基づく会話（出典付き）を行えます。
- ストレージは次の2つのモードに対応（ハイブリッドは廃止）：
  - ローカル（PGVector）
  - クラウド（OpenAI Vector Store）

選び方
- 設定パネルの「PDF Storage Mode」で選択します（グローバル設定）。
  - ローカル（PGVector）— 完全ローカル運用に適しています。
  - クラウド（OpenAI Vector Store）— マネージドなインデックスで手軽に開始。
- 既定は `PDF_STORAGE_MODE`（`local`／`cloud`）で設定します。後方互換のため `PDF_DEFAULT_STORAGE` も未設定時に参照します。

リストと操作
- PDFデータベースパネルにはローカルとクラウドの両リストが表示されます。
- どちらも Refresh、個別削除（確認あり）、Clear All（確認あり）をサポート。
- クラウドにアップロード後は自動的にクラウドリストを更新します。

検索
- ローカル： PGVector 類似検索（アプリに標準装備のローカル関数ツールを使用）。
- クラウド： OpenAI Responses API に File Search を自動注入。

環境変数
- `PDF_STORAGE_MODE` — 既定ストレージ（`local`／`cloud`）。
- `PDF_DEFAULT_STORAGE` — レガシー互換（`PDF_STORAGE_MODE` 未設定時のフォールバック）。
- `OPENAI_VECTOR_STORE_ID` — 既存の Vector Store を再利用。未設定なら初回インポート時に自動作成されます。

コスト（クラウド）
- OpenAI Vector Store は保存サイズ×時間（GB・日単位）で課金。ファイルが付いていない空のストアは実質コストほぼゼロです。

削除ポリシー（クラウド）
- 個別削除： Vector Store からデタッチし、Files からも削除（該当ベクターは検索対象外）。
- Clear All：
  - `OPENAI_VECTOR_STORE_ID` 設定あり → ストア本体は残し、ファイルを全削除（空）。
  - 設定なし → ストア本体を削除。
- FAQ：「Files を削除してストアが残っていると検索できる？」→ いいえ。ファイルが0ならヒットは0です。

レジストリ
- `~/monadic/data/document_store_registry.json` にアプリ別の Vector Store ID とファイルの記録（file_id／hash など）を保存します（原子的に書き込み）。
