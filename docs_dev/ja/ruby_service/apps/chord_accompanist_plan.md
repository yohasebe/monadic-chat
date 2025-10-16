# Chord Accompanist マルチエージェントプラン

## 目標
伴奏生成ワークフローを特化したエージェントが処理する個別のステージに再構築することで、無限検証ループを排除します。

## 提案されたエージェント
1. **RequirementsAgent**
   - テンポ、拍子、キー、楽器スタイル、希望する長さを収集。
   - 検証されたデフォルトを持つ`requirements.json`オブジェクトを出力。

2. **ProgressionAgent**
   - 要件とオプションの参照曲を取得。
   - JSON形式で構造化されたコード進行（小節ごと）を生成（例：`{ sections: [{ name: "Verse", bars: ["C", "G" ...] }] }`）。
   - 仮定を説明する責任がある（例：ヴァースに8小節を選択）。

3. **ArrangementAgent**
   - 進行とスタイルテンプレートを組み合わせてABCスケルトンを生成。
   - ローカルに保存された決定論的テンプレート（アルペジオ、ブロックコード、ウォーキングベース）を適用。
   - ABCの構造的正確性を保証（ヘッダー、小節区切り、単一ボイス）。

4. **ValidationAgent**
   - ABCJS検証とプレビューを実行。
   - 失敗時：自動修正を試みる（小節長の調整、末尾コンテンツの削除）。
   - N回試行後も失敗する場合は、ループする代わりに失敗サマリーを返す。

5. **SummaryAgent**（オプション）
   - 最終的なユーザーメッセージを作成（要件要約、プレビューリンク、ABCコード）。

## データフロー
```
ユーザー入力 -> RequirementsAgent -> requirements.json
requirements.json -> ProgressionAgent -> progression.json
requirements + progression -> ArrangementAgent -> draft.abc
ValidationAgent(draft.abc) -> { success, final_abc, preview }
Success -> SummaryAgent -> ユーザーレスポンス
Failure -> SummaryAgent -> 失敗を説明
```

## 実装ステップ
1. `requirements.json`と`progression.json`のJSONスキーマをドラフト。
2. マルチエージェント呼び出しをオーケストレーションするためにMDSLを更新。
3. テンプレートと検証用のRubyヘルパーを構築。
4. 典型的な会話をシミュレートする統合テストを作成。

## 実装ノート（2025-10-02）
- MDSLに明示的なペイロード要件を持つ`run_multi_agent_pipeline`ツールエントリを追加し、メインアシスタントが入力を収集した後にのみ呼び出すようにしました。
- `ChordAccompanist::Pipeline`を導入し、Requirement/Progression生成（構造化JSON経由）、決定論的アレンジメントテンプレート、および統合メタデータ伝播をカプセル化します。
- 決定論的アレンジメントは、現在、ASCII専用のコードパーサーと未知のシンボルのフォールバック処理を持つblock、pulse、arpeggioパターンをサポートしています。
- 検証はRubyツールレイヤーに残ります：サニタイズされたABCはABCJSに供給されます。検証失敗は元のエラーメッセージと共に`success: false`を返すことでループを中断します。
- ネットワーク呼び出しとAPI依存関係を回避するために、完全に指定された入力を使用してパイプラインを実行するユニットスペック（`spec/unit/chord_accompanist_pipeline_spec.rb`）を追加しました。
- パイプラインは、構造化された`notes`ペイロード（例：`requirements: {...}; progression_hint: [...]`）をパースするため、アシスタントは上流エージェントに再連絡することなく事前計算されたデータを渡すことができます。JSONの抽出はパースが失敗した場合のデフォルトにフォールバックします。
