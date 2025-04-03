# Monadic Chat Web インターフェース

![](../assets/images/monadic-chat-web.png ':size=700')

## チャット設定画面

![](../assets/images/chat-settings.png ':size=700')

**Base App** <br />
Monadic Chatであらかじめ用意された基本アプリの中から1つを選択します。各アプリでは異なるデフォルト・パラメター値が設定されており、固有の初期プロンプトが与えられています。各アプリの特徴については [Base Apps](#base-apps)を参照してください。

**Model** <br />
選択中のアプリで使用可能なモデルが表示されます。各アプリでデフォルトのモデルがある場合、あらかじめ選択状態で表示されますが、目的に応じて変更することができます。

!> 多くの基本アプリではモデルのリストをAPI経由で取得しており、複数のモデルが選択可能です。デフォルトのモデル以外を使用する場合はエラーとなる場合もあります。

**Reasoning Effort** <br />
OpenAIの高度な推論が可能なモデル（`o1`や`o3-mini`）では、推論に用いるトークン数を調整することができます。`low`を選択すると、推論過程のトークン数が最小限に抑えられ、`high`を選択すると、推論過程のトークン数が最大限になります。デフォルトは`medium`はその中間です。

**Max Tokens** <br />
チェックマークをオンにすると、APIに送信されるテキスト（過去のやりとりと新たなメッセージ）を指定されたトークン数に限定します。トークンのカウント方法についてはモデルによって異なります。OpenAIのモデルに関しては、[What are tokens and how to count them](https://help.openai.com/en/articles/4936856-what-are-tokens-and-how-to-count-them)を参照してください。

数値入力フォームには、APIにパラメターとして送られる「トークンの最大値」を指定します。これにはプロンプトとして送られるテキストのトークン数と、レスポンスとして返ってくるテキストのトークン数が含まれます。OpenAIのAPIにおけるトークンのカウント方法については[What are tokens and how to count them](https://help.openai.com/en/articles/4936856-what-are-tokens-and-how-to-count-them)を参照してください。

**Max Context Size** <br />
現在進行中のチャットに含まれるやりとりの中で、アクティブなものとして保つ発話の最大数です。アクティブな発話のみがOpenAIのchat APIに文脈情報として送信されます。インアクティブな発話も画面上では参照可能であり、エクスポートの際には保存対象となります。

**Parameters**<br />

下記の要素はパラメターとしてAPIに送られます。各パラメターの詳細はChat APIの[Reference](https://platform.openai.com/docs/api-reference/chat)を参照してください。なお、選択中のモデルで使用できないパラメターは無視されます。

- Temperature
- Top P
- Presence Penalty
- Frequency Penalty

**Show Initial Prompt**<br />
初期プロンプトとしてAPIに送られるテキスト（システムプロンプトと呼ばれることもあります）を表示または編集するにはオンにします。初期プロンプトによって、会話のキャラクター設定や、レスポンスの形式などを指定することができます。各アプリ の目的に応じたデフォルトのテキストが設定されていますが、自由に変更することが可能です。

**Show Initial Prompt for AI-User**<br />
AIユーザー機能を有効にしたときAIユーザーに与えられる初期プロンプトを表示します。AIユーザーが有効なとき、最初のメッセージは（AIでない）ユーザー自身が作成する必要があります。それ以降はAIアシスタントからのメッセージの内容に応じて、AIが「ユーザーになりきって」メッセージを代わりに作成してくれます。テキストボックスに入力されたAIユーザーによるメッセージをユーザー自身が編集したり、追記したりすることができます。

**Prompt Caching**<br />
APIに送信されるプロンプトをキャッシュするかどうかを指定します。キャッシュを有効にすると、API側で同じプロンプトが再利用されるため、APIの使用量を節約できます。またレスポンスタイムも向上します。現時点ではAnthropicのClaudeモデルにのみ対応しており、システムプロンプト、画像、PDFに限られます。

**Math Rendering**<br />
AIエージェントに数式を表示するときにはMathJax形式を使用するよう依頼し、レスポンス中の数式をMathJaxでレンダリングします。

**AI User Provider**<br />
AIユーザー機能で使用するプロバイダーをドロップダウンメニューから選択します。ドロップダウンには、設定で有効なAPIトークンを設定したプロバイダーのみが表示されます。AIユーザー機能は、あたかも人間のユーザーが書いたかのような応答を自動生成し、会話のテストや異なる入力に対するアシスタントの反応を確認するのに役立ちます。アシスタントが返信した後、AIユーザーボタンをクリックすると、会話の履歴に基づいて自然な後続メッセージが生成され、送信前に編集することができます。この機能は複数のプロバイダー（OpenAI、Claude、Gemini、Cohere、Mistral、Perplexity、DeepSeek、Grok）をサポートし、プロバイダー固有のフォーマット要件を適切に処理します。特にPerplexityのような厳格なメッセージ順序要件を持つプロバイダーも適切に対応します。

**Start from assistant**<br />
オンにすると、会話を始める時にアシスタント側が最初の発話を行います。

**Chat Interaction Controls**<br />
Monadic Chatを音声入力による会話に適した形に設定するためのオプションです。音声入力による会話を行う場合には、以下のオプション（`Start from assistant`, `Auto speech`, `Easy submit`）をすべてオンにするとよいでしょう。`check all` または `uncheck all` をクリックすることで、すべてのオプションを一括でオンまたはオフにすることができます。

**Auto speech**<br />

オンにすると、アシスタントからのレスポンスが返ってくるタイミングで自動的に合成音声での読み上げが行われます。合成音声のボイス、発話スピード、および使用言語（自動または個別指定）webインターフェイス上で選択可能です。

**Easy submit**<br />

オンにすると、`Send`ボタンをクリックしなくても、キーボードのEnterキーを押すと自動的にテキストエリア内のメッセージが送信されます。もし音声入力中であれば、Enterキーを押すか、`Stop`ボタンをクリックすることで、自動的にメッセージが送信されます。

**Start Session** <br />
このボタンをクリックすると、GPT Settingsで指定したオプションやパラメターのもとにチャットが開始されます。

## 基本情報パネル

![](../assets/images/monadic-chat-info.png ':size=400')

**Monadic Chat Info**<br />
関連するウェブサイトへのリンクとMonadic Chatのバージョンが示されます。`API Usage`をクリックするとOpenAIのページにアクセスします。API Usageで示されるのはAPI使用量の全体であり、Monadic Chatによるものだけとは限らないことに注意してください。バージョン番号の後の括弧には、Monadic Chatを使用する様式に応じて、DockerもしくはLocalが表示されます。通常はDockerが表示されます。

**Current Base App**<br />
現在選択している基本アプリの名前と説明が表示されます。Monadic Chatの起動時にはデフォルトのアプリである`Chat`に関する情報が表示されます。

## ステータスパネル

![](../assets/images/monadic-chat-status.png ':size=400')

**Monadic Chat Status**<br />

Monadic Chatの現在の状況を示します。

**Model Selected**<br />

現在選択されているモデルを表示します。

**Model Chat Stats**<br />

現在のセッションにおいて交わされたメッセージの数やトークンの数などの詳細が示されます。

## セッション表示パネル

![](../assets/images/monadic-chat-session.png ':size=400')

**Reset**<br />
`Reset`ボタンをクリックすると、現在の会話が破棄され、初期状態に戻ります。アプリの選択もデフォルトの`Chat`に戻ります。

**Settings**<br />
`Settings`ボタンをクリックすると、現在の会話を破棄しないで、GPT Settingsパネルに戻ります。その後、現在の会話に戻るには`Continue Session`をクリックします。

**Import**<br />
`Import`ボタンをクリックすると、現在の会話を破棄し、外部ファイル（JSON）に保存した会話データを読み込みます。また、外部ファイルに保存された設定が適用されます。

**Export**<br />
`Export`ボタンをクリックすると、現在の設定項目の値と会話データを外部ファイル（JSON）に保存します。

## 音声設定パネル

![](../assets/images/monadic-chat-tts.png ':size=400')

**Text-to-Speech Provider**<br />
音声合成に使用するプロバイダーを選択します。API Tokenが設定されていれば、OpenAI（NormalまたはHD）とElevenLabsの音声が選択可能です。

**Text-to-Speech Voice**<br />
音声合成に使用するボイスを指定できます。

**Text-to-Speech Speed**<br />
合成音声の再生速度を0.7（遅い）から1.2（速い）の範囲で調整できます。ElevenLabsの音声は、OpenAIの音声と比較して、変更された速度でテキストを再生する際の品質が一般的に優れています。

**Speech-to-Text (STT) Language**<br />
音声認識にはSpeech-to-Text APIを用いており、`Automatic` が選択されていると異なる言語による音声入力を自動で認識します。特定の言語を指定したい場合にはセレクターで言語を選択してください。
参考：[Whisper API FAQ](https://help.openai.com/en/articles/7031512-whisper-api-faq)

## PDFデータベース表示パネル

![](../assets/images/monadic-chat-pdf-db.png ':size=400')

?> このパネルはPDF読み込み機能を備えたアプリを選択しているときだけ表示されます。

**Uploaded PDF**<br />
ここには、`Import PDF`ボタンをクリックしてアップロードしたPDFのリストが表示されます。PDFをアップロードする際に、ファイルに個別の表示名を付けることができます。指定しない場合はオリジナルのファイル名が使用されます。複数のPDFファイルをアップロードすることが可能です。PDFファイル表示名の右側のゴミ箱アイコンをクリックするとそのPDFファイルの内容が破棄されます。

!> PDFファイルから得た情報はテキスト埋め込みに変換されて、PGVectorデータベースに格納されます。Monadic Chatをアップデートしたり、コンテナを再構築したりする際にはPDFテキスト埋め込みのデータベースが破棄されますので、後でリストアするために`Export Document DB`機能でデータをエクスポートしてください。
