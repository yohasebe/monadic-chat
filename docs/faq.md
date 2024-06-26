---
title: Monadic Chat
layout: default
---

# Frequently Asked Questions

[English](/monadic-chat/faq) |
[日本語](/monadic-chat/faq_ja)

---

**Q**: How can I obtain an API token for OpenAI?

**A**: You can create an account at the following URL. Please note that the OpenAI API account is separate from the ChatGPT account. Even if you subscribe to ChatGPT Plus, it does not give you access to the API token.

- [OpenAI: Welcome to the OpenAI platform](https://platform.openai.com)
- [Sign Up](https://platform.openai.com/signup)

---

**Q**: Where can I find the pricing for the API?

**A**: Please refer to the following page on OpenAI's website.

- [OpenAI: Pricing](https://openai.com/pricing#language-models)

Monadic Chat uses the following APIs:

- [GPT-4](https://platform.openai.com/docs/models/gpt-4) (High-performance large language model)
- [Whisper](https://platform.openai.com/docs/models/whisper) (Speech recognition model)
- [DALL·E 3](https://platform.openai.com/docs/models/dall-e) (Image generation model)
- [Vision](https://platform.openai.com/docs/guides/vision) (Image recognition model)
- [Embedding V3](https://platform.openai.com/docs/models/embeddings) (Text embedding model)

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
