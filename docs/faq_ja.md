---
title: Monadic Chat
layout: default
---

# よくある質問

[English](/monadic-chat/faq) |
[日本語](/monadic-chat/faq_ja)

---

**Q**: OpenAIのAPIトークンはどのように取得できますか？

**A**: 下記のURLでアカウント作成を行うことができます。OpenAIのAPIアカウントはChatGPTのアカウントとは別であることに注意してください。ChatGPT Plusをサブスクライブしていても、それだけではAPI Tokenを得ることはできません。

- [OpenAI: Welcome to the OpenAI platform](https://platform.openai.com)
- [Sign Up](https://platform.openai.com/signup)

---

**Q**: APIの試用料金はどこに書いてありますか？

**A**: OpenAIの下記ページをご覧ください。

- [OpenAI: Pricing](https://openai.com/pricing#language-models)

なお、Monadic Chatでは下記のAPIを使用します

- [GPT-4](https://platform.openai.com/docs/models/gpt-4)（高性能大規模言語モデル）
- [Whisper](https://platform.openai.com/docs/models/whisper) （音声認識モデル）
- [DALL·E 3](https://platform.openai.com/docs/models/dall-e) (画像生成モデル)
- [Vision](https://platform.openai.com/docs/guides/vision) （画像認識モデル）
- [Embedding V3](https://platform.openai.com/docs/models/embeddings) （テキスト埋込モデル）

<script src="https://cdn.jsdelivr.net/npm/jquery@3.5.0/dist/jquery.min.js"></script>
<script src="https://cdn.jsdelivr.net/npm/lightbox2@2.11.3/src/js/lightbox.js"></script>

---

<script>
  function copyToClipBoard(id){
    var copyText =  document.getElementById(id).innerText;
    document.addEventListener('copy', function(e) {
        e.clipboardData.setData('text/plain', copyText);
        e.preventDefault();
      }, true);
    document.execCommand('copy');
    alert('copied');
  }
</script>
