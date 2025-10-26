# Chord Accompanist プロトタイプノート

**現在の実装:**
- ABC記譜法はRubyとJS側の両方で正規化されます（HTML デコード、Unicodeダッシュ/引用符 → ASCII、繰り返しの空行の折りたたみ、括弧のクリーンアップ）。
- 検証は、Mermaid Grapherアプローチを模倣して、Selenium内でABCJSを使用します。
- 現在のワークフロー：`validate_abc_syntax` → `analyze_abc_error`（必要な場合） → 応答。
- 実装済みツール：`validate_chord_progression`、`validate_abc_syntax`、`analyze_abc_error`

**提案された機能（未実装）:**
- `preview_abc`：スコアをレンダリングしてPNGをキャプチャします。MIDIサポートはまだ配線されていませんが、ファイル名は将来の使用のために予約されています。
- `run_multi_agent_pipeline`：アシスタントの構造化されたペイロード（`context` + `notes`）を受け入れることができます。`notes`がJSON形式のセグメント（`requirements: {...}; progression_hint: [...]`）を含む場合、Ruby側はそれらを抽出し、追加のLLM呼び出しをスキップして、ツールの再試行ループを減らします。

将来の作業に関する考慮事項：
- ABCJS APIが統合されたら、ダウンロード可能なSVG/MIDIを公開する。
- 自動コード進行テンプレートまたは参照ベースの推論を追加する。
- サニタイザーの回帰テスト（Unicodeダッシュ、スマート引用符、余分な空行）を含める。
