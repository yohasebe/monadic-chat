---
title: Monadic Chat
layout: default
---

# Development
{:.no_toc}

[English](/monadic-chat/development) |
[日本語](/monadic-chat/development_ja)

## Table of Contents
{:.no_toc}

1. toc
{:toc}


## Installation without Docker Desktop

🚧 UNDER CONSTRUCTION

- Ruby (recommended version: 3.1 or above)
- Rust (required for tokenization)
- PostgreSQL + [pgvector](https://github.com/pgvector/pgvector) (used as the Vector database)

## Developing Base Apps

🚧 UNDER CONSTRUCTION

## File Organization

🚧 UNDER CONSTRUCTION

## Available Options

🚧 UNDER CONSTRUCTION

##  Function Calling in Ruby

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
