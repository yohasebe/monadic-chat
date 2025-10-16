# Chord Accompanist プロトタイプノート

- ABC記譜法はRubyとJS側の両方で正規化されます（HTML デコード、Unicodeダッシュ/引用符 → ASCII、繰り返しの空行の折りたたみ、括弧のクリーンアップ）。
- 検証は、Mermaid Grapherアプローチを模倣して、Selenium内でABCJSを使用します。
- `preview_abc`はスコアをレンダリングしてPNGをキャプチャします。MIDIサポートはまだ配線されていませんが、ファイル名は将来の使用のために予約されています。
- ワークフローはMermaid Grapherを模倣します：`validate_abc_syntax` → `preview_abc` → 応答。
- `run_multi_agent_pipeline`はアシスタントの構造化されたペイロード（`context` + `notes`）を受け入れることができます。`notes`がJSON形式のセグメント（`requirements: {...}; progression_hint: [...]`）を含む場合、Ruby側はそれらを抽出し、追加のLLM呼び出しをスキップして、ツールの再試行ループを減らします。

将来の作業に関する考慮事項：
- ABCJS APIが統合されたら、ダウンロード可能なSVG/MIDIを公開する。
- 自動コード進行テンプレートまたは参照ベースの推論を追加する。
- サニタイザーの回帰テスト（Unicodeダッシュ、スマート引用符、余分な空行）を含める。
