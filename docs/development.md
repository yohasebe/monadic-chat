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

## Installation and Launch without Using Docker Desktop

### Dependencies

#### Ruby

Recommended version is 3.1 or above

#### PostgreSQL + pgvector

PostgreSQL and pgvector module are required for storing and searching vectors

- [pgvector](https://github.com/pgvector/pgvector)

### Installation

```bash
$ git clone https://github.com/yohasebe/monadic-chat.git
$ cd monadic-chat
$ bundle install
$ chmod -R +x ./bin
```

### Start/Stop/Restart Monadic Chat

`start`

```bash
# pwd: monadic-chat
$ ./bin/monadic start
```

`stop`

```bash
# pwd: monadic-chat
$ ./bin/monadic stop
```

`restart`

```bash
# pwd: monadic-chat
$ ./bin/monadic restart
```

### Update Monadic Chat

```bash
# pwd: monadic-chat
$ git pull
```

## Basic App Development

### Directory/File Structure

```text
apps
├── chat
│   └── chat_app.rb
├── code
│   └── code_app.rb
├── language_practice
│   └── language_practice_app.rb
├── language_practice_plus
│   └── language_practice_plus_app.rb
├── linguistics
│   └── linguistics_app.rb
├── math
│   └── math_app.rb
├── novel
│   └── novel_app.rb
├── pdf
│   └── pdf_app.rb
├── translate
│   └── translate_app.rb
├── voice_chat
│   └── voice_chat_app.rb
├── wikipedia
│   └── wikipedia_app.rb
└── NEW_APP_FOLDER
    └── NEW_APP.rb
```

### Example App File in Ruby

```ruby
# All basic apps inherit from the MonadicApp class
class AppName < MonadicApp
  # The icon is represented by the <i> tag (using FontAwesome)
  def icon
    "<i class='fas fa-comments'></i>"
  end

  # The description of the app
  def description
    "This is the standard application for monadic chat. It can be used in basically the same way as ChatGPT."
  end

  # The initial system prompt used
  def initial_prompt
    text = <<~TEXT
      You are a friendly and professional consultant with real-time, up-to-date information about almost anything. You are able to answer various types of questions, write computer program code, make decent suggestions, and give helpful advice in response to a prompt from the user. If the prompt is not clear enough, ask the user to rephrase it. Use the same language as the user and insert an emoji that you deem appropriate for the user's input at the beginning of your response.
    TEXT
    text.strip
  end

  # The settings of the app represented as a hash
  def settings
    {
      # The app name displayed on the screen
      "app_name": "Chat",
      # The app icon displayed on the screen (defined above as icon)
      "icon": icon,
      # The app description (defined above as description)
      "description": description,
      # The default system prompt (defined above as initial_prompt)
      "initial_prompt": initial_prompt,
      # The default OpenAI GPT model
      "model": "gpt-3.5-turbo-0125",
      # The default temperature
      "temperature": 0.5,
      # The default top_p
      "top_p": 0.0,
      # The default max_tokens
      "max_tokens": 1000,
      # The default context size (number of messages held as active)
      "context_size": 10,
      # The default easy_submit (if true, user can submit by pressing Enter)
      "easy_submit": false,
      # The default auto_speech (if true, response is automatically read out)
      "auto_speech": false,
      # The default initiate_from_assistant (if true, assistant speaks first)
      "initiate_from_assistant": false,
      # Whether to display a form to upload PDFs and store them in Vector DB
      "pdf": false,
      # Whether to render $$-enclosed equations with MathJax (inline equations are enclosed in $)
      "mathjax": false,
      # If function calls are needed, provide the function definitions (see below)
      "functions": [],
      # Use Monadic mode (see below)
      "monadic": false
    }
  end
end
```

### Function Calls in Ruby

🚧 UNDER CONSTRUCTION


### About Monadic Mode

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
