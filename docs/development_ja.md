---
title: Monadic Chat
layout: default
---

# 開発
{:.no_toc}

[English](/monadic-chat/development) |
[日本語](/monadic-chat/development_ja)

## Table of Contents
{:.no_toc}

1. toc
{:toc}

🚧 UNDER CONSTRUCTION

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
