# FAQ：音声入力と音声合成

##### Q: AIエージェントと音声による会話を行うことはできますか？ :id=voice-conversation

**A**: はい、可能です。Webインターフェイスの **Interaction** パネルで`Auto speech`と`Easy submit`を両方オンにしてください。音声入力のボタンにフォーカスが移るので、Enter キーで音声入力を始めて終えられます（Easy Submit がオンのときは、右矢印キーでも始められます）。入力が終わるとメッセージが自動で送られ、応答が読み上げられます。途切れないハンズフリーの会話には、Live Conversation のアプリを使ってください。

---

##### Q: OpenAIやElevenLabsのAPIキーなしでテキスト読み上げ（TTS）を使用できますか？ :id=tts-without-api-key

**A**: はい。Gemini、Mistral、xAI Grok もそれぞれの API キーで声を提供しています。キーがまったくなくても、Text-to-Speech Providerドロップダウンで「Web Speech API」オプションを使用できます。これはブラウザの内蔵音声合成機能を使用し、APIキーは必要ありません。利用可能な声はオペレーティングシステムとブラウザに依存しますが、ほとんどの最新ブラウザはこの機能をサポートしています。

---

##### Q: Web Speech APIをテキスト読み上げに使用する場合、どのように声を選択しますか？ :id=web-speech-api-voices

**A**: Text-to-Speech Providerで「Web Speech API」を選択すると、システムで利用可能なすべての声を表示するドロップダウンメニューが表示されます。これらの声はオペレーティングシステムとブラウザによって提供されます。異なるオペレーティングシステム（Windows、macOS、Linux）では、異なる声のオプションが利用可能です。

---

##### Q: どの音声認識モデルが利用可能で、どのように選択しますか？ :id=stt-model-selection

**A**: Monadic Chatは複数の音声認識プロバイダーをサポートしています：

- **OpenAIモデル**: 精度と機能が異なる複数のモデル。高度なモデルは複数人の音声における話者識別（ダイアライゼーション）をサポートします。
- **Google Gemini**: 柔軟な言語認識と多言語サポートによる高度な音声理解を提供します。
- **ElevenLabs Scribe**: 単語レベルのタイムスタンプを備えた高精度の音声認識。ElevenLabs APIキーが必要です。
- **Cohere**: Cohere Transcribeモデルによる音声認識。Cohere APIキーが必要です。
- **Mistral Voxtral**: MistralのVoxtral Transcribeモデルによる音声認識。Mistral APIキーが必要です。
- **xAI**: xAIによる音声認識。xAI APIキーが必要です。

**Speech** パネルの **Speech-to-Text Model** ドロップダウンで希望のモデルを選択できます。利用可能なモデルは設定されたAPIキーに基づいて有効になります。選択内容はブラウザーの Cookie に保存され、セッションをまたいで保持されます。

---

##### Q: AIエージェントの音声の速度を調整することはできますか？ :id=voice-speed-adjustment

**A**: はい、**Speech** パネルの`TTS Speed`スライダーを使って、合成音声の再生速度を調整できます。速度は0.7（遅い）から1.2（速い）の範囲で調整可能です。Web Speech APIも速度調整をサポートしていますが、品質はブラウザやオペレーティングシステムによって異なる場合があります。Gemini の Flash と Flash-Lite は再生のときに速度を変えるので、Speech Draft Helperアプリでこれらを使って保存する音声ファイルは標準の速さです。Pro の TTS には、リクエストで速さを伝えます。

---

##### Q: Gemini TTSとは何ですか？他のプロバイダーとの違いは？ :id=gemini-tts-overview

**A**: Gemini TTSはGoogleのテキスト読み上げサービスで、**Speech** パネルのプロバイダードロップダウンからFlashとFlash-LiteのTTSを選択できます。Gemini APIキーが必要で、チャット応答の音声再生とSpeech Draft Helperアプリでのオーディオファイル生成の両方に対応しています。利用できる音声と言語はGoogle側の提供内容であり、Monadic Chatとは独立して変わります。利用できるものは **Speech** パネルの音声ドロップダウンで確認できます。

---

##### Q: 音声合成の際に実際の言語とは異なる言語で再生されることがあります。どうすればいいですか？ :id=tts-language-detection

**A**: **Conversation Language** が自動のときは、読み上げの言語がテキストから決まるので、複数の言語が混ざったテキストは別の言語で読まれることがあります。**Conversation Language** を使っている言語に設定してください。この設定は音声認識だけでなく、音声合成にも渡されます。

---

##### Q: 入力テキストを音声合成してオーディオファイルとして保存することはできますか？ :id=saving-audio-files

**A**: はい、`Speech Draft Helper`アプリを選択して、テキストを入力した上で、オーディオファイルに変換するようにAIエージェントに指示することで、音声合成した結果をファイルとして保存することができます。Speech Draft Helperは複数のTTSプロバイダーをサポートしています：OpenAIとElevenLabsはMP3ファイルを出力し、GeminiはWAVファイルを出力します。オーディオ生成時に異なる音声とプロバイダーを選択できます。

