---
title: Monadic Chat
layout: default
---

# 開発
{:.no_toc}

[English](/monadic-chat-web/development) |
[日本語](/monadic-chat-web/development_ja)

## Table of Contents
{:.no_toc}

1. toc
{:toc}

## Docker Desktopを使わないインストール

🚧 UNDER CONSTRUCTION

- Ruby (3.1以上を推奨)
- Rust (tokenizationに必要)
- PostgreSQL (Vectorデータベースとして利用)
- [pgvector](https://github.com/pgvector/pgvector

## 基本アプリの開発

🚧 UNDER CONSTRUCTION

## ファイル構成

🚧 UNDER CONSTRUCTION

## 利用可能なオプション

🚧 UNDER CONSTRUCTION

## Rubyでの関数呼び出し

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
