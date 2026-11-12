# 図解・可視化アプリ

説明やデータから図を作るアプリです。Mermaid と Draw.io の図、言語学の樹形図、LaTeX/TikZ による概念図を作れます。

## Mermaid Grapher

![Mermaid Grapher app icon](../assets/icons/diagram-draft.png ':size=40')

[Mermaid.js](https://mermaid.js.org/) の図でデータを視覚化するアプリです。データや指示を入力すると、AI が Mermaid のコードを書き、チャットの横の[作業画面](../basic-usage/web-interface.md#work-screen)に図を表示します。図は共有フォルダの会話のフォルダにある `.mmd` のファイルです。返答にはそのパスが書かれ、返答の下の行からもう一度表示できます。**描画** と **ソースコード** で図とコードを切り替えます。

チャットでは、図は **SVG をダウンロード** の付いた画像として表示されます。上の切り替えで Mermaid のコードを表示できます。図の中に書いた設定（`%%{init: …}%%` や frontmatter）は使えません。その図は描かれず、理由が表示されます。どのアプリの返答に入った Mermaid のコードも、このように描かれます。

**主な機能：**
- **図の種類の選択**：データに合う図の種類を AI が選びます（フローチャート、シーケンス図、クラス図、状態図、ER 図、ガントチャート、円グラフ、サンキー図、マインドマップなど）
- **描画の確認**：図は、表示する前に Selenium コンテナのブラウザで Mermaid.js によって描画されます。Mermaid がエラーを返すと、AI はコードを直して描き直します
- **見た目の確認**：AI は描画された図のスクリーンショットを見て、レイアウトの問題がないか確かめてから回答します
- **エラーの分析**：コードに構文エラーがあると、AI がエラーを分析して直し方を示します
- **Web 検索**：あまり使われない種類の図では、AI が Mermaid.js のドキュメントを調べられます

Mermaid Grapher の対応プロバイダーは[モデル対応状況の表](../basic-usage/basic-apps.md#app-availability)を参照してください。


## DrawIO Grapher

![DrawIO Grapher app icon](../assets/icons/diagram-draft.png ':size=40')

必要な図を説明すると、Draw.io の図を作るアプリです。AI が Draw.io の XML を書き、構造を確かめて直し、チャットの横の[作業画面](../basic-usage/web-interface.md#work-screen)に図を表示します。図は共有フォルダの会話のフォルダにある `.drawio` のファイルです。返答にはそのパスが書かれ、返答の下の行からもう一度表示できます。**描画** と **元の文字** で図と XML を切り替えます。

**主な機能：**
- **XML の確認と修復**：生成された Draw.io の XML を確かめ、よくある構造の問題を直します
- **図の種類**：フローチャート、UML の図（クラス図、シーケンス図、アクティビティ図）、ER 図、ネットワーク図、組織図、マインドマップ、BPMN、ベン図、ワイヤーフレームなど
- **ファイル**：図はそのたびに新しい `.drawio` ファイルになるので、前の図も残ります。Draw.io で開いて編集を続けられます。共有フォルダの別の場所に写しを保存するときは、ファイル名と場所を指定してください

DrawIO Grapher の対応プロバイダーは[モデル対応状況の表](../basic-usage/basic-apps.md#app-availability)を参照してください。


## Syntax Tree

![Syntax Tree app icon](../assets/icons/syntax-tree.png ':size=40')

いろいろな言語の文から、言語学の樹形図（統語樹）を作るアプリです。文の文法構造を分析し、[RSyntaxTree](https://yohasebe.github.io/rsyntaxtree/) で樹形図を描きます。主な機能：

- 英語、日本語、中国語などの多くの言語に対応。右から左に書く言語の文は左右を反転し、最初の語を右端に置いて描きます
- 文の語を一列に並べ、それぞれを点線で節点につなげます
- 移動は、痕跡やコピーから移動先への矢印で描きます。分析しない句は三角形の下に描きます
- ベクターグラフィックのエディターで編集できる SVG で出力

樹形図は、透明な背景の SVG 画像として、チャットの横の[作業画面](../basic-usage/web-interface.md#work-screen)に表示されます。SVG は共有フォルダの会話のフォルダ（`conversations/…/artifacts/`）に保存され、返答にはそのパスが書かれます。LaTeX のソースを頼むと、樹形図を `.tex` ファイル（LaTeX の forest）として SVG の横に保存します。移動の矢印はソースには入りません。

Syntax Tree の対応プロバイダーは[モデル対応状況の表](../basic-usage/basic-apps.md#app-availability)を参照してください。


## Concept Visualizer :id=concept-visualizer

![Concept Visualizer app icon](../assets/icons/diagram-draft.png ':size=40')

概念や関係を自然な言葉で説明すると、図にするアプリです。LaTeX/TikZ で、いろいろな種類の図を描きます。主な機能：

- **図の種類**：マインドマップ、フローチャート、組織図、ネットワーク図、年表、ベン図、3D のプロット（散布図、曲面）など
- **自然な言葉での入力**：視覚化したい内容を説明するだけで使えます
- **分野**：ビジネス、教育、科学、技術の図
- **言語**：中国語、日本語、韓国語を含む多くの言語のテキスト

図は SVG と PNG で共有フォルダに保存されます。SVG はベクターグラフィックのエディターで編集できます。

Concept Visualizer には LaTeX が必要です。**Actions → Install Options** で **Install LaTeX (minimal set for diagrams)** をオンにし、Python コンテナを再ビルドしてください。対応プロバイダーは[モデル対応状況の表](../basic-usage/basic-apps.md#app-availability)を参照してください。
